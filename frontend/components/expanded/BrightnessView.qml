import QtQuick
import "../../core"
import ".."

// The expanded view of the brightness face (K24): the backlight level as a slider (intent
// brightness.set). The service reads the backlight on demand, so the level is the last reading.
// No reading yet shows a dot, and no backlight shows as such, never as 0 % (Shōjiki). Watches
// svc.brightness only while it is on screen (Ma).
Column {
    id: view
    width: parent.width
    spacing: Theme.gap

    Watch { doc: "svc.brightness" }
    readonly property var d: Store.docs["svc.brightness"]
    readonly property bool loaded: d !== undefined
    readonly property bool present: loaded && d.present === true
    readonly property real level: present ? Math.max(0, Math.min(1, (d.percent ?? 0) / 100)) : 0
    readonly property string origin: "qs:stage"

    Text {
        width: view.width
        color: Theme.fg
        font.pixelSize: Theme.fsTitle
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.brightness.heading")
    }
    Row {
        visible: view.loaded
        width: view.width
        spacing: Theme.gap
        Text {
            width: 20
            height: Theme.controlH
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: view.present ? Theme.accent : Theme.dim
            font.pixelSize: Theme.fs + 2
            font.family: Theme.fam(text, Theme.families)
            text: "☼"
        }
        Slider {
            height: Theme.controlH
            width: view.width - 20 - readout.width - 2 * Theme.gap
            value: view.level
            unavailable: !view.present
            a11y: I18n.tr("island.brightness.heading")
            onMoved: v => Store.intent("brightness.set", v, view.origin)
        }
        Text {
            id: readout
            width: 64
            height: Theme.controlH
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: view.present ? Math.round(view.level * 100) + "%" : ""
        }
    }
    Text {
        visible: !view.loaded || !view.present
        width: view.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: view.loaded ? I18n.tr("frontend.brightness.unavailable") : "…"
    }
}
