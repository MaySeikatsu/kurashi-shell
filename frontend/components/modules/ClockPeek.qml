import QtQuick
import "../../core"
import ".."

// The clock module's peek (K72 retrofit, BACKLOG I223; docs/ux/edge-modules.md "Module variants"): the day in full and the
// ISO week, one fact a line (PeekLines). What comes next on the day — the calendar's next event, the nearest timer's end
// — is the mods' to add through a slot `clock.peek.lines` once this peek is served (W92 row 3, BACKLOG I602: the core
// names no mod, K28). A second time zone needs a field the daemon does not send yet (CONTRACT-CHANGE row 551). Hosted by
// the Stage like every peek (K35; the core source `clock:main`, row 550); it watches what it reads only while it shows
// (Ma) and computes nothing but formats: the date is the daemon's.
PeekLines {
    id: cp
    Watch { doc: "svc.clock" }

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
    lines: {
        var out = []
        if (!day) return [I18n.tr("edge-modules.clock.no_time")]
        out.push(day.toLocaleDateString(loc, dayFmt))
        out.push(fill(I18n.tr("edge-modules.clock.week"), { n: isoWeek(day) }))
        return out
    }
}
