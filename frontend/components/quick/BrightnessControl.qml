import QtQuick
import "../../core"

// The display's brightness (svc.brightness): a level, set by the intent `brightness.set`, not a switch; the page has the
// level (DisplayPage). Without a backlight it is inert and says so. W70: the logic QuickPanel held.
Control {
    id: c
    mid: "brightness"
    page: "display"
    Watch { doc: "svc.brightness"; active: c.live }
    readonly property var d: Store.docs["svc.brightness"] || ({})
    readonly property bool ok: d.present === true
    readonly property real level: ok ? Math.max(0, Math.min(1, Number(d.percent || 0) / 100)) : 0
    known: Store.docs["svc.brightness"] !== undefined
    label: I18n.tr("island.quick.tile.display")
    glyph: "☼"
    icon: "light_mode"
    // A bar's mark: the level in three steps.
    readonly property string glanceIcon: level < 0.34 ? "brightness_5" : level < 0.67 ? "brightness_6" : "brightness_7"
    reason: ok ? "" : I18n.tr("island.quick.tile.no_backlight")
    forcedBy: String(d.forced_by || "")
    toggles: false
    value: ok ? Math.round(Number(d.percent || 0)) + " %" : ""
    // The level's intent (the daemon clamps and answers with the document); `origin` names the view that sends it.
    function set(v, origin) {
        if (!ok) return
        Store.intent("brightness.set", Math.max(0, Math.min(1, v)), origin)
    }
}
