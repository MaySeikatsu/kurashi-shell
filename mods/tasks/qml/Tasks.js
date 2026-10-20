.pragma library

// Shared reads of the `mod.tasks` document for the desk cards, the panel and the widget (docs/ux/tasks.md). Pure
// functions over what the daemon sent, plus one hand-off: what the panel should show when a desk card opens it.

// What the next panel open shows: "" (the list), "add" (the add field focused), "notes" (the note tab). The desk card sets
// it right before `mod.panel.open`; the panel reads and clears it when it is made. A `.pragma library` script is one
// instance per engine, so the desk (a bottom-layer window) and the Stage share it.
var intent = ""

// Open items first, in file order, then the done ones the daemon kept (today's, with `show_done`).
function ordered(tasks) {
    var open = [], done = []
    for (var i = 0; i < (tasks || []).length; i++) (tasks[i].done ? done : open).push(tasks[i])
    return open.concat(done)
}

// "2026-10-21" as a local noon Date (no timezone slip at midnight), or null.
function dateOf(iso) {
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso || ""))
    return m ? new Date(+m[1], +m[2] - 1, +m[3], 12) : null
}

// Days from `today` (svc.clock's date) to `due`: 0 today, 1 tomorrow, negative when late; null without both.
function daysTo(due, today) {
    var a = dateOf(today), b = dateOf(due)
    if (!a || !b) return null
    return Math.round((b - a) / 86400000)
}

// The due chip's words: "Today", "Tomorrow", "Yesterday", else the short date in the UI locale.
function dueLabel(tr, due, today, locale) {
    var n = daysTo(due, today)
    if (n === 0) return tr("mod-tasks.due.today")
    if (n === 1) return tr("mod-tasks.due.tomorrow")
    if (n === -1) return tr("mod-tasks.due.yesterday")
    var d = dateOf(due)
    if (!d) return ""
    return d.toLocaleDateString(Qt.locale(locale), locale.indexOf("ja") === 0 ? "M月d日" : "d MMM")
}

function isLate(task, today) {
    var n = daysTo(task.due, today)
    return !task.done && n !== null && n < 0
}

// Priority 1..3 (⏫ 🔼 🔽) as marks: the count says it, the colour only adds to it.
function priorityMark(p) {
    return p === 1 ? "!!!" : p === 2 ? "!!" : p === 3 ? "!" : ""
}

// "{n} more" style fills.
function fill(s, vars) {
    return String(s).replace(/\{(\w+)\}/g, function (m, k) { return vars[k] !== undefined ? String(vars[k]) : m })
}

// The note's first lines for the desk: blank lines and Markdown heading or list marks dropped, at most `max` lines.
function noteLines(text, max) {
    var out = []
    var lines = String(text || "").split(/\r?\n/)
    for (var i = 0; i < lines.length && out.length < max; i++) {
        var s = lines[i].replace(/^\s*(#{1,6}\s+|[-*+]\s+(\[[ xX]\]\s+)?|>\s?)/, "").trim()
        if (s !== "") out.push(s)
    }
    return out
}

// A long path with its middle elided: "~/Documents/…/Tasks.md".
function shortPath(p, home) {
    var s = String(p || "")
    if (home && s.indexOf(home + "/") === 0) s = "~" + s.substring(home.length)
    if (s.length <= 44) return s
    return s.substring(0, 18) + "…" + s.substring(s.length - 24)
}
