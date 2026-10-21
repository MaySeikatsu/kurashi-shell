.pragma library

// Shared reads of the `mod.calendar` document (docs/ux/calendar.md) for the agenda, the day dots, the desk card, the
// bar widget and the island face. Pure functions over what the daemon sent: the daemon gives unix seconds, the views
// compute "now", "in 10 min" and "until 14:00" from the clock while they are visible.

function fill(s, vars) {
    return String(s).replace(/\{(\w+)\}/g, function (m, k) { return vars[k] !== undefined ? String(vars[k]) : m })
}

function pad(n) { return (n < 10 ? "0" : "") + n }

// yyyy-MM-dd of a Date in local time: the document's day keys.
function key(d) {
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

// Local midnight of a day key, as unix seconds (null for a bad key).
function dayStart(k) {
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(k || ""))
    return m ? new Date(+m[1], +m[2] - 1, +m[3]).getTime() / 1000 : null
}

function nextKey(k) {
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(k || ""))
    return m ? key(new Date(+m[1], +m[2] - 1, +m[3] + 1)) : ""
}

// 24-hour HH:mm of a unix second (kurashi writes times the same in en and ja).
function hm(t) {
    var d = new Date(t * 1000)
    return pad(d.getHours()) + ":" + pad(d.getMinutes())
}

function events(doc, k) {
    return (doc && doc.days && doc.days[k]) || []
}

// The time column of an event on day `k`: "All day", "09:00–09:15", "until 14:00", "from 22:00".
function timeLabel(tr, ev, k) {
    var s = dayStart(k), e = s === null ? null : dayStart(nextKey(k))
    if (ev.all_day) return tr("mod-calendar.all_day")
    if (s === null) return hm(ev.start)
    var before = ev.start < s, after = ev.end > e
    if (before && after) return tr("mod-calendar.all_day")
    if (before) return fill(tr("mod-calendar.until"), { time: hm(ev.end) })
    if (after) return fill(tr("mod-calendar.from"), { time: hm(ev.start) })
    if (ev.end <= ev.start) return hm(ev.start)
    return hm(ev.start) + "–" + hm(ev.end)
}

function isRunning(ev, now) { return !ev.all_day && ev.start <= now && now < ev.end }
function isPast(ev, now) { return ev.end <= now && !(ev.end === ev.start && ev.start > now - 60) }

// Every timed instance from today on that has not ended, once each (a multi-day event is on several days), by start.
function upcoming(doc, now, todayKey) {
    var out = [], seen = {}
    var days = (doc && doc.days) || {}
    var keys = Object.keys(days).filter(function (k) { return k >= todayKey }).sort()
    for (var i = 0; i < keys.length; i++) {
        var list = days[keys[i]]
        for (var j = 0; j < list.length; j++) {
            var ev = list[j]
            if (ev.all_day || seen[ev.id]) continue
            if (ev.end > now || (ev.end === ev.start && ev.start >= now)) { seen[ev.id] = true; out.push(ev) }
        }
    }
    out.sort(function (a, b) { return a.start - b.start || (a.title < b.title ? -1 : 1) })
    return out
}

// The event the bar and the island name: the running one, else the next to start within `horizon` seconds; null.
function next(doc, now, todayKey, horizon) {
    var list = upcoming(doc, now, todayKey)
    for (var i = 0; i < list.length; i++) {
        if (isRunning(list[i], now)) return list[i]
    }
    return list.length > 0 && list[0].start - now <= horizon ? list[0] : null
}

// "now", "in 5 min", "in 2 h 10 min", "tomorrow 09:00", "Mon 09:00".
function relative(tr, ev, now, todayKey, loc) {
    if (isRunning(ev, now)) return fill(tr("mod-calendar.now_until"), { time: hm(ev.end) })
    var mins = Math.max(0, Math.ceil((ev.start - now) / 60))
    var startKey = key(new Date(ev.start * 1000))
    if (startKey === todayKey) {
        if (mins < 60) return fill(tr("mod-calendar.in_min"), { n: mins })
        return fill(tr("mod-calendar.in_h_min"), { h: Math.floor(mins / 60), n: mins % 60 })
    }
    if (startKey === nextKey(todayKey)) return fill(tr("mod-calendar.tomorrow_at"), { time: hm(ev.start) })
    return new Date(ev.start * 1000).toLocaleDateString(loc, "ddd") + " " + hm(ev.start)
}

// The age of a cached copy: "5 min", "3 h", "2 d".
function age(tr, s) {
    if (s < 3600) return fill(tr("mod-calendar.age.min"), { n: Math.max(1, Math.round(s / 60)) })
    if (s < 172800) return fill(tr("mod-calendar.age.h"), { n: Math.round(s / 3600) })
    return fill(tr("mod-calendar.age.d"), { n: Math.round(s / 86400) })
}

// One line per source that is not plainly ready: "Work: offline · copy from 2 h ago", "Home: the file is missing".
function notes(tr, doc, now) {
    var out = []
    var list = (doc && doc.sources) || []
    for (var i = 0; i < list.length; i++) {
        var s = list[i]
        if (s.state === "ready" || s.state === "loading") continue
        var t = s.name + ": " + tr(s.reason || ("mod-calendar.state." + s.state))
        if (s.fetched_at) t += " · " + fill(tr("mod-calendar.copy_from"), { age: age(tr, now - s.fetched_at) })
        out.push({ text: t, error: s.state === "error" || s.state === "missing" })
    }
    return out
}

// The accessible line of an event.
function a11y(tr, ev, k) {
    var parts = [timeLabel(tr, ev, k), ev.title || tr("mod-calendar.untitled")]
    if (ev.location) parts.push(ev.location)
    if (ev.calendar) parts.push(ev.calendar)
    return parts.join(", ")
}
