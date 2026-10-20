import QtQuick
import "../../core"
import ".."

// The expanded view of the brightness face (K24; island brief 5): the built-in display's backlight as a slider with its
// read-back (intent brightness.set). Other displays get their reason: the backlight is the only method so far, and external
// monitors need DDC/CI, which is not supported yet. Night light says why it cannot be offered: no service serves it. The
// backlight level is the last reading (the service reads it on demand); no reading yet is a dot, and no backlight is said
// as such, never as 0 % (Shōjiki). Watches svc.brightness and svc.workspaces (the displays) only while on screen (Ma).
Column {
    id: view
    width: parent.width
    spacing: Theme.gap

    Watch { doc: "svc.brightness" }
    Watch { doc: "svc.workspaces" }
    readonly property var d: Store.docs["svc.brightness"]
    readonly property bool loaded: d !== undefined
    readonly property bool present: loaded && d.present === true
    readonly property real level: present ? Math.max(0, Math.min(1, (d.percent ?? 0) / 100)) : 0
    readonly property string origin: "qs:stage"
    // The displays the compositor reports: the keys of the workspaces document's outputs, less the "*" entry.
    readonly property int displayCount: Object.keys((Store.docs["svc.workspaces"] || ({})).outputs || ({})).filter(function (k) { return k !== "*" }).length

    Text {
        width: view.width
        color: Theme.fg
        font.pixelSize: Theme.fsTitle
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.brightness.heading")
    }
    StaleNote { face: "brightness" }

    // One row per display that can be adjusted: the built-in panel (the backlight) for now.
    Text {
        visible: view.present
        width: view.width
        elide: Text.ElideRight
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.brightness.builtin") + " · " + (view.d.device ?? "")
    }
    Row {
        visible: view.loaded
        width: view.width
        spacing: Theme.gap
        Icon {
            id: sun
            width: 24
            height: Theme.controlH
            name: view.level < 0.5 ? "brightness_5" : "brightness_7"
            glyph: "☼"
            filled: true
            size: Theme.fs + 6
            color: view.present ? Theme.warning : Theme.dim
        }
        Slider {
            height: Theme.controlH
            width: view.width - sun.width - readout.width - 2 * Theme.gap
            fill: Theme.warning
            value: view.level
            unavailable: !view.present
            a11y: I18n.tr("island.brightness.builtin")
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
            font.weight: Theme.wMedium
            font.features: { "tnum": 1 }
            font.family: Theme.fam(text, Theme.families)
            text: view.present ? Math.round(view.level * 100) + "%" : ""
        }
    }
    Text {
        visible: !view.loaded || !view.present
        width: view.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: view.loaded ? I18n.tr("error.brightness.no_device") : "…"
    }
    Text {
        visible: view.displayCount > 1
        width: view.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.brightness.others")
    }

    // Night light: no service on this machine serves it, so the row says so instead of a switch.
    // W21: on a plate with its icon, inert (no switch) while nothing serves it.
    Rectangle {
        width: view.width
        height: nightCol.implicitHeight + 2 * Theme.gap
        radius: Theme.rLg
        color: Theme.containerHigh
        Icon {
            id: moon
            x: Theme.pad
            anchors.verticalCenter: parent.verticalCenter
            name: "nightlight"
            glyph: "☾"
            size: Theme.fs + 6
            color: Theme.dim
        }
        Column {
            id: nightCol
            anchors { left: moon.right; right: parent.right; leftMargin: Theme.gap; rightMargin: Theme.pad; verticalCenter: parent.verticalCenter }
            Text {
                width: parent.width
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("island.brightness.night")
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("island.brightness.night.none")
            }
        }
    }
}
