import QtQuick
import "../../../core"

// Gloss (W53.2): a glossy band — Windows XP's taskbar (docs/ux/styles.md §2, measured from guidebookgallery.org's
// pics/gui/desktop/full/winxppro.png, the bar at y 570–599): a dark line on the edge that faces the screen's middle, two
// px of a lighter blue (`[decor] bar.edge`), a short fall into the body (`bar.fill`'s first role), the body brightening a
// little toward the far edge and two darkening px on it. `bar.gloss` scales the light. Drawn across the bar's thickness,
// so a bar on any edge gets it (the light side faces the screen). Every colour from roles (rule 4); static.
BarBase {
    id: gb
    readonly property var fills: Theme.decor("bar.fill", [])
    readonly property color c: fills.length > 0 ? fills[0] : Theme.accent
    readonly property color c2: fills.length > 1 ? fills[1] : Qt.lighter(c, 1.03)
    readonly property string edgeRole: Theme.decor("bar.edge", "")
    readonly property color lit: edgeRole !== "" ? edgeRole : Qt.lighter(c, 1.35)
    readonly property real g: Math.max(0, Math.min(1, Theme.decor("bar.gloss", 0.5) * 2))
    // Thickness across the bar and the stops in px from the light (inner) edge.
    readonly property real t: Math.max(1, vertical ? width : height)
    readonly property bool flip: inner === "bottom" || inner === "right"
    function at(px) { var p = Math.max(0, Math.min(1, px / t)); return flip ? 1 - p : p }
    function tint(col, a) { return Qt.tint(col, Qt.rgba(1, 1, 1, a)) }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: gb.vertical ? Gradient.Horizontal : Gradient.Vertical
            GradientStop { position: gb.at(0); color: gb.tint(gb.c, 0.08 * gb.g) }
            GradientStop { position: gb.at(1); color: Qt.tint(gb.c, Qt.alpha(gb.lit, 0.55 * gb.g)) }
            GradientStop { position: gb.at(2.2); color: Qt.tint(gb.c, Qt.alpha(gb.lit, 0.75 * gb.g)) }
            GradientStop { position: gb.at(3.2); color: Qt.tint(gb.c, Qt.alpha(gb.lit, 0.25 * gb.g)) }
            GradientStop { position: gb.at(5.5); color: Qt.darker(gb.c, 1.03) }
            GradientStop { position: gb.at(gb.t * 0.4); color: Qt.darker(gb.c, 1.03) }
            GradientStop { position: gb.at(gb.t * 0.8); color: gb.c2 }
            GradientStop { position: gb.at(gb.t - 3); color: gb.c }
            GradientStop { position: gb.at(gb.t - 1.5); color: Qt.darker(gb.c, 1.12) }
            GradientStop { position: gb.at(gb.t); color: Qt.darker(gb.c, 1.35) }
        }
    }
}
