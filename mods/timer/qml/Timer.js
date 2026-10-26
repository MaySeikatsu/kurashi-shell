// Helpers of the timer mod (K73, docs/ux/timer.md). The views only draw: every state is the daemon's, and the time left is
// interpolated from the deadline the document carries (`ends_at_ms`), so a view that wakes late is still right.
// The document lists the timers nearest end first, running ones before paused ones before ended ones.
.pragma library

function pad(n) {
    return (n < 10 ? "0" : "") + n
}

// "mm:ss", or "h:mm" from an hour up. Rounded up, so the last second reads 00:01 and 00:00 only once the time is up.
function clock(ms) {
    var s = Math.max(0, Math.ceil(ms / 1000))
    if (s >= 3600) return Math.floor(s / 3600) + ":" + pad(Math.floor((s % 3600) / 60))
    return pad(Math.floor(s / 60)) + ":" + pad(s % 60)
}

// The local clock time of a moment, "HH:MM".
function hhmm(ms) {
    return Qt.formatTime(new Date(ms), "HH:mm")
}

// The time left on a timer at `now` (Unix ms): from its end while it runs, what was kept while it is paused, nothing once
// it ended.
function left(t, now) {
    if (!t) return 0
    if (t.state === "running") return Math.max(0, t.ends_at_ms - now)
    if (t.state === "paused") return t.remaining_ms
    return 0
}

// The share of its length still to run (0..1): the ring draws it.
function share(t, now) {
    if (!t || !(t.duration_ms > 0)) return 0
    return Math.min(1, Math.max(0, left(t, now) / t.duration_ms))
}

// The timer the glance, the peek and the face speak for: the first of the list (nearest end), or null.
function nearest(timers) {
    var list = timers || []
    return list.length > 0 ? list[0] : null
}

// The first running timer, or null: what the island's live face counts down (the list puts running timers first).
function firstRunning(timers) {
    var list = timers || []
    for (var i = 0; i < list.length; i++) {
        if (list[i].state === "running") return list[i]
    }
    return null
}

// How long the island's end face stays up after an end: the daemon's END_TTL_MS (K24, shared.rs).
var END_WINDOW_MS = 12000

// The timer whose end the island's end face speaks for: the first that ended within END_WINDOW_MS before `now`, or null.
// Pass the clock the view ticks with, so the window closes on time.
function justEnded(timers, now) {
    var list = timers || []
    for (var i = 0; i < list.length; i++) {
        var t = list[i]
        if (t.state === "ended" && now - t.ended_at_ms <= END_WINDOW_MS) return t
    }
    return null
}

// The first timer of a kind ("countdown" or "pomodoro"), or null.
function first(timers, kind) {
    var list = timers || []
    for (var i = 0; i < list.length; i++) {
        if (list[i].kind === kind) return list[i]
    }
    return null
}

// How many timers run now.
function runningCount(timers) {
    var n = 0
    var list = timers || []
    for (var i = 0; i < list.length; i++) {
        if (list[i].state === "running") n++
    }
    return n
}

// "{k}" placeholders of an i18n text, filled from `vars`.
function fill(text, vars) {
    return String(text).replace(/\{(\w+)\}/g, function (m, k) {
        return vars[k] !== undefined ? String(vars[k]) : m
    })
}

// The name a timer shows: its label, else the default of its kind (the caller passes the translated defaults).
function nameOf(t, fallback) {
    var label = t && t.label ? String(t.label).trim() : ""
    return label !== "" ? label : fallback
}

// A typed length: "mm" (minutes) or "mm:ss". Returns the arguments of `timer.start`, or null when it is neither or is out
// of the range a timer may have (a minute to a day).
function parseLength(text) {
    var m = /^(\d{1,4})(?::([0-5]?\d))?$/.exec(String(text || "").trim())
    if (!m) return null
    var minutes = parseInt(m[1], 10)
    if (m[2] === undefined) {
        if (minutes < 1 || minutes > 1440) return null
        return {minutes: minutes}
    }
    var total = minutes * 60 + parseInt(m[2], 10)
    if (total < 1 || total > 1440 * 60) return null
    return {seconds: total}
}

// A QML colour as a CSS string for a Canvas: "rgba(r, g, b, a)" (Qt's own string form is #AARRGGBB, which Canvas misreads).
function css(c, alpha) {
    var a = alpha === undefined ? c.a : alpha * c.a
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")"
}
