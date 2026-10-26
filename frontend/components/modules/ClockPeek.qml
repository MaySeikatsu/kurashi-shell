import QtQuick
import "../../core"
import "../../core/mods.js" as Mods
import ".."

// The clock module's peek (K72 retrofit, BACKLOG I223; docs/ux/edge-modules.md "Module variants"): the day in full, the
// ISO week, then the next thing on it when one exists — the next timed agenda item (the calendar mod) and the nearest
// timer's end (the timer mod) — one fact a line (PeekLines). A second time zone needs a field the daemon does not send yet
// (CONTRACT-CHANGE row 551). Hosted by the Stage like every peek (K35; the core source `clock:main`, row 550); it watches
// what it reads only while it shows (Ma) and computes nothing but formats: the date, the agenda and the timers are the
// daemon's.
PeekLines {
    id: cp
    Watch { doc: "svc.clock" }
    Watch { doc: "mods" }
    readonly property var modsDoc: Store.docs["mods"]
    readonly property bool calendarOn: Mods.qmlOf(modsDoc, "widget:calendar", "calendar") !== ""
    readonly property bool timerOn: Mods.qmlOf(modsDoc, "widget:timer", "timer") !== ""
    Watch { doc: "mod.calendar"; active: cp.calendarOn }
    Watch { doc: "mod.timer"; active: cp.timerOn }

    readonly property var clock: Store.docs["svc.clock"] || ({})
    readonly property string lang: (Store.docs["i18n"] || ({})).locale === "ja" ? "ja" : "en"
    readonly property var loc: Qt.locale(lang)
    readonly property string dayFmt: lang === "ja" ? "yyyy年M月d日（dddd）" : "dddd, d MMMM yyyy"
    // The daemon's day (yyyy-MM-dd, local), as a Date at local noon (no DST edge can move it to another day).
    readonly property var day: {
        var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(clock.date || ""))
        return m ? new Date(+m[1], +m[2] - 1, +m[3], 12) : null
    }
    // ISO 8601 week: the week with the year's first Thursday is week 1.
    function isoWeek(d) {
        var t = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 3 - (d.getDay() + 6) % 7, 12)
        var w1 = new Date(t.getFullYear(), 0, 4, 12)
        return 1 + Math.round(((t - w1) / 86400000 - 3 + (w1.getDay() + 6) % 7) / 7)
    }
    function fill(s, vars) { return String(s).replace(/\{(\w+)\}/g, function (m, k) { return vars[k] !== undefined ? String(vars[k]) : m }) }
    function hm(sec) { return Qt.formatTime(new Date(sec * 1000), "HH:mm") }

    // The next timed agenda item from today on that has not ended (the calendar mod's document: `days[<key>]` lists).
    readonly property var nextEvent: {
        if (!calendarOn || !day) return null
        var doc = Store.docs["mod.calendar"] || ({})
        var days = doc.days || {}, today = String(clock.date || ""), now = Date.now() / 1000, best = null
        for (var k in days) {
            if (k < today) continue
            var list = days[k] || []
            for (var i = 0; i < list.length; i++) {
                var ev = list[i]
                if (ev.all_day || !(ev.end > now || ev.start >= now)) continue
                if (best === null || ev.start < best.start) best = ev
            }
        }
        return best
    }
    // The nearest timer that runs (the timer mod lists the nearest end first).
    readonly property var nextTimer: {
        if (!timerOn) return null
        var list = (Store.docs["mod.timer"] || ({})).timers || []
        for (var i = 0; i < list.length; i++) if (list[i].state === "running") return list[i]
        return null
    }

    lines: {
        var out = []
        if (!day) return [I18n.tr("edge-modules.clock.no_time")]
        out.push(day.toLocaleDateString(loc, dayFmt))
        out.push(fill(I18n.tr("edge-modules.clock.week"), { n: isoWeek(day) }))
        if (nextEvent) {
            var now = Date.now() / 1000
            out.push(fill(I18n.tr(nextEvent.start <= now ? "edge-modules.clock.event_now" : "edge-modules.clock.event_next"),
                          { title: nextEvent.title || I18n.tr("mod-calendar.untitled"), time: hm(nextEvent.start) }))
        }
        if (nextTimer)
            out.push(fill(I18n.tr("edge-modules.clock.timer_ends"),
                          { name: nextTimer.name || I18n.tr("mod-timer.name.timer"), time: hm(nextTimer.ends_at_ms / 1000) }))
        return out
    }
}
