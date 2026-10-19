import QtQuick
import "../../core"

// volume: transient OSD from svc.audio (icon + level bar + percent; muted and unavailable are
// shown as such, never as a stale level: Shōjiki). When the daemon names the output ("Headphones · 40 %",
// runtime.island.main detail.volume, I45), that line replaces the percent; the island does not pass it in.
// On a side bar: the icon over the bare figure (the pill is 28 px wide, so no sign); the full line is the accessible name.
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
    Watch { doc: "svc.audio"; active: f.live }
    Watch { doc: "runtime.island.main"; active: f.live }

    wantW: row.implicitWidth
    wantH: col.implicitHeight
    Row {
        id: row
        visible: !f.vertical
        anchors.centerIn: parent
        spacing: Theme.gap
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: f.avail && !f.muted ? Theme.accent : Theme.dim
            font.pixelSize: Theme.fs
            text: f.glyph
        }
        Rectangle {
            visible: f.avail
            anchors.verticalCenter: parent.verticalCenter
            width: 90; height: 4; radius: 2
            color: Theme.outline
            Rectangle {
                width: parent.width * f.level
                height: parent.height; radius: 2
                color: f.muted ? Theme.dim : Theme.accent
                // Short; runs only while the level changes under a live face.
                Behavior on width {
                    enabled: f.animate && f.live
                    NumberAnimation { duration: Theme.stdMs / 2; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve }
                }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
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
        Text {
            Accessible.ignored: true
            color: f.avail && !f.muted ? Theme.accent : Theme.dim
            font.pixelSize: Theme.fs
            text: f.glyph
        }
        Text {
            Accessible.ignored: true
            visible: f.avail && !f.muted
            color: Theme.fg
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: Math.round(f.level * 100)
        }
    }
}
