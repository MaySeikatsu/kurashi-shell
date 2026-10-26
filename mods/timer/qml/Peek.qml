import QtQuick
import qs.components
import "Timer.js" as T

// The timer peek (K73, docs/ux/timer.md "Peek"): each timer's name, the time left and the clock time it ends, one line each;
// a paused one says so, an ended one says its time is up. The Stage draws it on hover or focus of the glance (K35); it
// watches the document only while it shows (Ma).
PeekLines {
    id: peek
    // Handed in by ModLoader (K26); the core singletons are imported too.
    required property var store
    required property var theme
    required property var i18n

    Component.onCompleted: peek.store.watch("mod.timer")
    Component.onDestruction: peek.store.unwatch("mod.timer")

    readonly property var d: peek.store.docs["mod.timer"] || ({})

    function tr(key) { return peek.i18n.tr(key) }
    function defaultName(t) {
        return t.kind === "pomodoro" ? tr("mod-timer.name.pomodoro") : tr("mod-timer.name.timer")
    }

    lines: {
        var out = []
        if (d.available !== true) return out
        var list = d.timers || []
        var now = Date.now()
        for (var i = 0; i < list.length && i < 4; i++) {
            var t = list[i]
            var name = T.nameOf(t, defaultName(t))
            if (t.state === "running") {
                out.push(T.fill(tr("mod-timer.peek.line"), {
                    label: name, time: T.clock(T.left(t, now)), ends: T.hhmm(t.ends_at_ms)
                }))
            } else if (t.state === "paused") {
                out.push(T.fill(tr("mod-timer.peek.line.paused"), { label: name, time: T.clock(t.remaining_ms) }))
            } else {
                out.push(T.fill(tr("mod-timer.peek.line.ended"), { label: name }))
            }
        }
        return out
    }
}
