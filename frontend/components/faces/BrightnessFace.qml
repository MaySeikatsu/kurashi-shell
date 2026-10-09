import QtQuick
import "../../core"

// brightness: transient OSD from svc.brightness (glyph + level bar + percent). The service reads the
// backlight on demand, so the level is the last reading, not a live one. No reading yet, and no
// backlight, are shown as such, never as 0% (Shōjiki).
FaceBase {
    id: f
    readonly property var d: Store.docs["svc.brightness"]
    readonly property bool loaded: d !== undefined
    readonly property bool present: loaded && d.present === true
    readonly property real level: present ? Math.max(0, Math.min(1, (d.percent ?? 0) / 100)) : 0
    Watch { doc: "svc.brightness"; active: f.live }

    wantW: row.implicitWidth
    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.gap
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: f.present ? Theme.accent : Theme.dim
            font.pixelSize: Theme.fs
            text: f.present ? "☼" : (f.loaded ? "⊘" : "…")
        }
        Rectangle {
            visible: f.present
            anchors.verticalCenter: parent.verticalCenter
            width: 90; height: 4; radius: 2
            color: Theme.outline
            Rectangle {
                width: parent.width * f.level
                height: parent.height; radius: 2
                color: Theme.accent
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
            text: !f.loaded ? "…"
                  : (f.present ? Math.round(f.level * 100) + "%" : I18n.tr("frontend.brightness.unavailable"))
        }
    }
}
