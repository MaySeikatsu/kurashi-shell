import QtQuick
import "../../core"

// Rule (W53.6): the rule `[decor] title.rule` / `bar.rule` names, across the item's width in `ink` — `single` (a device-
// pixel hairline), `double` (NieR:Automata's header rule: a 2 px line over a hairline, 2 px apart), `filigree` (an
// ornament rule, Filigree.qml) — `fade` lets a line thin out toward both ends (a game's gold hairline). `flip` puts the
// heavy line of a double below. Its height is what it draws: 0 for `none`. Static.
Item {
    id: r
    property string kind: "none"
    property color ink: Theme.fg
    property bool fade: false
    property bool flip: false
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property real heavy: Theme.crisp(2, Screen.devicePixelRatio)
    implicitHeight: kind === "single" ? hair : kind === "double" ? heavy + 2 + hair : kind === "filigree" ? 12 : 0
    visible: implicitHeight > 0

    component Line: Rectangle {
        width: r.width
        gradient: r.fade ? fadeGrad : null
        color: r.ink
        readonly property Gradient fadeGrad: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(r.ink, 0) }
            GradientStop { position: 0.2; color: r.ink }
            GradientStop { position: 0.8; color: r.ink }
            GradientStop { position: 1; color: Qt.alpha(r.ink, 0) }
        }
    }
    Line { visible: r.kind === "single"; height: r.hair }
    Line { visible: r.kind === "double"; y: r.flip ? r.hair + 2 : 0; height: r.heavy }
    Line { visible: r.kind === "double"; y: r.flip ? 0 : r.heavy + 2; height: r.hair }
    Filigree {
        visible: r.kind === "filigree"
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(r.width, 280)
        height: 12
        ink: r.ink
    }
}
