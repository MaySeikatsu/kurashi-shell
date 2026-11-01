import QtQuick
import "../../../core"
import ".."

// Band (W53.6): a game menu's header band as the bar's ground — NieR:Automata's tab band (a flat parchment strip with the
// faint grid, the thick-and-thin rule along its foot), a dark-fantasy HUD shade (Dark Souls: a dark band fading out toward
// the screen's middle over a gold hairline) or an ornate one (Hollow Knight: an ornament rule centred under it). `[decor]
// bar.fill` (one role solid, two a gradient from the screen's edge inward; [] = the surface) at the material's alpha, the
// look's pattern over it, `bar.fade` (the fill thins to nothing toward the screen's middle) and `bar.rule` (Rule.qml) in
// `bar.edge` ("" = the text's ink) along the inner edge — fading at its ends while the band fades. Colours from roles
// (rule 4); static.
BarBase {
    id: bb
    readonly property var fills: Theme.decor("bar.fill", [])
    readonly property color from: fills.length > 0 ? fills[0] : Theme.surface
    readonly property color to: fills.length > 1 ? fills[1] : from
    readonly property real a: Theme.tok("color.surface_alpha", 1)
    readonly property bool fades: Theme.decor("bar.fade", false) === true
    readonly property string edgeRole: Theme.decor("bar.edge", "")
    readonly property bool flip: inner === "top" || inner === "left"

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: bb.vertical ? Gradient.Horizontal : Gradient.Vertical
            GradientStop { position: bb.flip ? 1 : 0; color: Qt.alpha(bb.from, bb.a) }
            GradientStop { position: 0.55; color: Qt.alpha(Qt.tint(bb.from, Qt.alpha(bb.to, 0.5)), bb.fades ? bb.a * 0.7 : bb.a) }
            GradientStop { position: bb.flip ? 0 : 1; color: Qt.alpha(bb.to, bb.fades ? 0 : bb.a) }
        }
    }
    Pattern { anchors.fill: parent; visible: !bb.fades }
    Rule {
        kind: Theme.decor("bar.rule", "none")
        ink: bb.edgeRole !== "" ? bb.edgeRole : Theme.fg
        fade: bb.fades
        flip: bb.inner === "top"
        visible: !bb.vertical && kind !== "none"
        width: kind === "filigree" ? Math.min(bb.width, 280) : bb.width
        x: Math.round((bb.width - width) / 2)
        y: bb.inner === "bottom" ? bb.height - height : 0
    }
}
