import QtQuick
import QtQuick.Shapes
import "../../../core"

// Stamp (session 28): a seal. Off, the empty frame a seal would go in, drawn in the dim ink; on, the seal pressed in
// the accent, a touch askew as a hand presses it, with its mark cut out in the paper's colour. It comes down from a
// little above (a stamp) over the fast time. For the looks of paper and ink.
ToggleBase {
    id: tg
    property bool hovered: false
    readonly property real corner: 5
    implicitWidth: 26
    implicitHeight: 26
    opacity: enabled ? 1 : 0.5
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.min(5, Theme.rFull)
        color: "transparent"
        border.width: 1.5
        border.color: tg.hovered ? Theme.fg : Theme.dim
        visible: !tg.checked || seal.scale > 1.01
    }
    Rectangle {
        id: seal
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.min(5, Theme.rFull)
        rotation: -5
        color: Theme.colorOr("toggle.track.on", Theme.accent)
        opacity: tg.checked ? (tg.pressed ? 0.8 : 1) : 0
        scale: tg.checked ? (tg.pressed ? 0.94 : 1) : 1.35
        Behavior on scale { enabled: Theme.springOn; NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot } }
        Behavior on opacity { enabled: Theme.timed; NumberAnimation { duration: Theme.fastMs } }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Theme.fgOnAccent; strokeWidth: 2.4; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                PathSvg { path: "M 6.5 12.5 L 10.5 16.5 L 17.5 8" }
            }
        }
    }
}
