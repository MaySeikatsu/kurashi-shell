import QtQuick
import "../../core"
import ".."
import "../island"

// volume: transient OSD from svc.audio (icon + level bar + percent; muted and unavailable are
// shown as such, never as a stale level: Shōjiki). When the daemon names the output ("Headphones · 40 %",
// runtime.island.main detail.volume, I45), that line replaces the percent; the island does not pass it in.
// On a side bar: the icon over the bare figure (the pill is 28 px wide, so no sign); the full line is the accessible name.
// W21: the level is a thick bar that fills from empty when the face appears and springs to each new level (Apple's and
// Capsule's OSD); the pill widens for it and swallows it back when the face goes.
FaceBase {
    id: f
    readonly property var d: Store.docs["svc.audio"] || ({})
    readonly property bool avail: d.available !== false
    readonly property bool muted: d.muted === true
    readonly property real level: Math.max(0, Math.min(1, d.volume ?? 0))
    readonly property string line: String(((Store.docs["runtime.island.main"] || ({})).detail || ({})).volume ?? "")
    readonly property string full: !f.avail ? I18n.tr("island.volume.unavailable")
        : (f.muted ? I18n.tr("island.volume.muted")
        : (f.line !== "" ? f.line : Math.round(f.level * 100) + "%"))
    readonly property string glyph: !f.avail || f.muted ? "⊘" : (f.level < 0.34 ? "♩" : "♪")
    readonly property string icon: !f.avail || f.muted ? "volume_off"
        : (f.level < 0.34 ? "volume_mute" : (f.level < 0.67 ? "volume_down" : "volume_up"))
    Watch { doc: "svc.audio"; active: f.live }
    Watch { doc: "runtime.island.main"; active: f.live }

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
            color: f.avail && !f.muted ? Theme.accent : Theme.dim
        }
        LevelMeter {
            visible: f.avail
            anchors.verticalCenter: parent.verticalCenter
            width: 96
            level: f.level
            color: f.muted ? Theme.dim : Theme.accent
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
            width: Math.min(implicitWidth, 200)
            elide: Text.ElideRight
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
            color: f.avail && !f.muted ? Theme.accent : Theme.dim
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
            visible: f.avail && !f.muted
            color: Theme.fg
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: Math.round(f.level * 100)
        }
    }
}
