import QtQuick
import qs.core
import qs.components.quick
import ".."
import "../Timer.js" as T

// The timer tile in quick settings (K28 slot `quick.tiles`, docs/ux/quick-settings.md, the QuickTile contract of
// docs/ux/COMPOSITION.md §5): on while a countdown runs, its subtitle the nearest timer's time left (or paused, or time is up).
// Its main zone starts the default countdown when none is on, pauses a running one, resumes a paused one, and dismisses an
// ended one; its arrow (Right) opens the panel. It subscribes to `mod.timer` and to nothing else; the second clock runs only
// while a countdown runs (Ma).
QuickTile {
    id: tile
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n

    Watch { doc: "mod.timer" }
    Tick { id: clock; wanted: tile.visible && tile.running }

    readonly property var d: Store.docs["mod.timer"] || ({})
    readonly property var nearest: T.nearest(d.timers)
    readonly property bool showing: nearest !== null && nearest !== undefined
    readonly property bool running: showing && nearest.state === "running"
    readonly property bool paused: showing && nearest.state === "paused"
    readonly property bool ended: showing && nearest.state === "ended"

    glyph: "⏱"
    label: I18n.tr("mod-timer.tile.label")
    subtitle: !showing ? I18n.tr("mod-timer.tile.idle")
        : running ? I18n.tr("mod-timer.tile.running").replace("{time}", T.clock(T.left(nearest, clock.now)))
        : paused ? I18n.tr("mod-timer.tile.paused").replace("{time}", T.clock(nearest.remaining_ms))
        : I18n.tr("mod-timer.tile.ended")
    on: running
    toggles: false
    acts: true
    hasPage: true

    onActivated: {
        if (!tile.showing) {
            Store.act("timer.start", {}, function () {})
        } else if (tile.running) {
            Store.act("timer.pause", { id: tile.nearest.id }, function () {})
        } else if (tile.paused) {
            Store.act("timer.resume", { id: tile.nearest.id }, function () {})
        } else {
            Store.act("timer.stop", { id: tile.nearest.id }, function () {})
        }
    }
    onPageRequested: Store.act("mod.panel.open", { id: "timer", panel: "timer" }, function () {})
}
