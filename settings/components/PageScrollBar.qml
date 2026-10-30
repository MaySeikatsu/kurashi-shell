import QtQuick
import QtQuick.Controls.Basic
import "../core"
import "decor"

// A page's scrollbar (session 17, docs/ux/settings.md): on the right edge, only while the page is taller than its view;
// thin at rest, wider under the pointer, grab it to drag the page, a click on the track pages. Pointer-only (the
// keyboard scrolls the page itself).
// W53 (contract row 591): in the look's scroll style (ScrollStyle) — its width where it sets one (a steady bar, as 9x's),
// a flat or bevelled thumb, or the look's scroll part drawing the whole bar (track, thumb, arrows that step a line).
ScrollBar {
    id: sb
    policy: ScrollBar.AsNeeded
    interactive: true
    minimumSize: 0.06
    readonly property bool wide: hovered || pressed
    ScrollStyle { id: ss }
    // The look's own width, steady (0 = today's thin bar that widens under the pointer).
    readonly property real fixedW: ss.width(0)
    padding: ss.has ? 0 : 2
    contentItem: Item {
        implicitWidth: sb.fixedW > 0 ? sb.fixedW - 2 * sb.padding : (sb.wide ? 8 : 5)
        Behavior on implicitWidth { enabled: Theme.springOn && sb.fixedW <= 0; NumberAnimation { duration: Theme.quickMs } }
        // Today's pill.
        Rectangle {
            anchors.fill: parent
            visible: !ss.has && ss.thumb === "pill"
            radius: width / 2
            color: Qt.alpha(Theme.fg, sb.pressed ? 0.6 : sb.wide ? 0.5 : 0.35)
            opacity: sb.size < 1 ? 1 : 0
        }
        // A flat or bevelled thumb (a gel is a part's).
        Loader {
            anchors.fill: parent
            active: !ss.has && ss.thumb !== "pill"
            sourceComponent: Rectangle {
                color: ss.thumb === "bevel" ? Theme.container : Qt.alpha(Theme.fg, sb.pressed ? 0.6 : 0.45)
                radius: ss.thumb === "gel" ? width / 2 : 0
                opacity: sb.size < 1 ? 1 : 0
                BevelEdge { anchors.fill: parent; visible: ss.thumb === "bevel"; w: Theme.crisp(1, Screen.devicePixelRatio) }
            }
        }
    }
    background: Item {
        implicitWidth: sb.fixedW > 0 ? sb.fixedW : 12
        // The look's scroll part: the whole bar, its arrows stepping a line.
        Loader {
            anchors.fill: parent
            active: ss.has
            source: active ? ss.part : ""
            onLoaded: {
                item.size = Qt.binding(function () { return sb.size })
                item.position = Qt.binding(function () { return sb.position })
                item.orientation = Qt.binding(function () { return sb.orientation })
                item.pressed = Qt.binding(function () { return sb.pressed })
                item.hovered = Qt.binding(function () { return sb.hovered })
                item.step.connect(function (d) { if (d > 0) sb.increase(); else sb.decrease() })
            }
        }
    }
    Accessible.role: Accessible.ScrollBar
}
