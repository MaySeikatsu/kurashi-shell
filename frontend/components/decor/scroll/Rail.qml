import QtQuick
import "../../../core"
import ".."

// Rail (W53.6): a game list's scroll bar — a hairline rail with a mark at each end (`[decor] scroll.cap`: NieR's squares,
// a dark-fantasy diamond, a pastel heart; Bullet.qml) and a slim thumb sliding along it (`scroll.thumb`: `flat` square
// ends, `pill` round), the rail and caps in the outline role, the thumb in the text's ink (darker while pressed). With
// `scroll.arrows` the caps step a line (they act: no dead button). `scroll.width` sets its thickness. Colours from roles
// (rule 4); static between moves.
ScrollBase {
    id: sb
    readonly property bool v: orientation === Qt.Vertical
    readonly property string cap: Theme.decor("scroll.cap", "none")
    readonly property bool arrows: Theme.decor("scroll.arrows", false) === true
    readonly property real t: v ? width : height
    readonly property real capS: cap === "none" ? 0 : Math.max(5, Math.round(t * 0.55))
    readonly property real ends: capS > 0 ? capS + 3 : 0
    readonly property real span: (v ? height : width) - 2 * ends
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property color railInk: Theme.color("color.outline", "#6b6657")

    Rectangle {
        color: sb.railInk
        opacity: 0.7
        x: sb.v ? Math.round((sb.width - sb.hair) / 2) : sb.ends
        y: sb.v ? sb.ends : Math.round((sb.height - sb.hair) / 2)
        width: sb.v ? sb.hair : sb.span
        height: sb.v ? sb.span : sb.hair
    }
    Rectangle {
        readonly property real len: Math.max(sb.t * 1.5, sb.span * Math.min(1, sb.size))
        readonly property real at: sb.ends + (sb.span - len) * Math.max(0, Math.min(1, sb.position / Math.max(0.0001, 1 - sb.size)))
        x: sb.v ? Math.round(sb.width * 0.25) : at
        y: sb.v ? at : Math.round(sb.height * 0.25)
        width: sb.v ? Math.max(2, Math.round(sb.width * 0.5)) : len
        height: sb.v ? len : Math.max(2, Math.round(sb.height * 0.5))
        radius: Theme.decor("scroll.thumb", "flat") === "pill" ? Math.min(width, height) / 2 : 0
        color: sb.pressed ? Qt.darker(Theme.fg, 1.2) : Theme.fg
        opacity: sb.hovered || sb.pressed ? 1 : 0.85
    }
    Repeater {
        model: sb.cap === "none" ? [] : [-1, 1]
        Item {
            required property int modelData
            width: sb.v ? sb.width : sb.capS
            height: sb.v ? sb.capS : sb.height
            x: sb.v ? 0 : (modelData < 0 ? 0 : sb.width - width)
            y: sb.v ? (modelData < 0 ? 0 : sb.height - height) : 0
            Bullet {
                anchors.centerIn: parent
                kind: sb.cap
                size: sb.capS
                ink: sb.railInk
            }
            MouseArea {
                anchors.fill: parent
                enabled: sb.arrows
                onClicked: sb.step(parent.modelData)
            }
        }
    }
}
