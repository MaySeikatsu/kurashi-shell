import QtQuick
import "../../core"
import ".."
import "../island"

// brightness: transient OSD from svc.brightness (icon + level bar + percent). The service reads the
// backlight on demand, so the level is the last reading, not a live one. No reading yet, and no
// backlight, are shown as such, never as 0% (Shōjiki). On a side bar: the icon over the bare figure.
// W21: the level is a thick bar that fills with a spring, as the volume face's.
FaceBase {
    id: f
    readonly property var d: Store.docs["svc.brightness"]
    readonly property bool loaded: d !== undefined
    readonly property bool present: loaded && d.present === true
    readonly property real level: present ? Math.max(0, Math.min(1, (d.percent ?? 0) / 100)) : 0
    readonly property string full: !f.loaded ? "…"
        : (f.present ? Math.round(f.level * 100) + "%" : I18n.tr("frontend.brightness.unavailable"))
    readonly property string icon: f.present ? (f.level < 0.5 ? "brightness_5" : "brightness_7") : ""
    readonly property string glyph: f.present ? "☼" : (f.loaded ? "⊘" : "…")
    Watch { doc: "svc.brightness"; active: f.live }

    wantW: row.implicitWidth
    wantH: col.implicitHeight
    Row {
        id: row
        visible: !f.vertical
        anchors.centerIn: parent
        spacing: Theme.gap
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: f.icon
            glyph: f.glyph
            filled: true
            size: Theme.fs + 5
            color: f.present ? Theme.warning : Theme.dim
        }
        LevelMeter {
            visible: f.present
            anchors.verticalCenter: parent.verticalCenter
            width: 96
            level: f.level
            color: Theme.warning
            animate: f.animate && f.live
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.weight: Theme.wMedium
            font.family: Theme.fam(text, Theme.families)
            font.features: { "tnum": 1 }
            text: f.full
        }
    }
    Column {
        id: col
        visible: f.vertical
        anchors.centerIn: parent
        Accessible.role: Accessible.StaticText
        Accessible.name: f.full
        Icon {
            Accessible.ignored: true
            anchors.horizontalCenter: parent.horizontalCenter
            color: f.present ? Theme.warning : Theme.dim
            name: f.icon
            glyph: f.glyph
            filled: true
            size: Theme.fs + 3
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            Accessible.ignored: true
            anchors.horizontalCenter: parent.horizontalCenter
            visible: f.present
            color: Theme.fg
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: Math.round(f.level * 100)
        }
    }
}
