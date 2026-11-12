import QtQuick
import "../core"

// Scroll edges (session 30, I494, docs/ux/session-30.md §2; `theme.material.scroll_edges`): content cut by a scrolling
// view's edge blends out — blurred more and faded more toward the edge, in a short zone, only at an edge where something
// is cut (the reference: iOS 26's sheets). Put it beside the view, in the same parent, after it:
//   Flickable { id: list; … }   ScrollEdge { view: list }
// It draws the view through a layer while the view can scroll at all (one look whether it rests at an end or not: the
// layer is not switched on and off as it scrolls); a view that fits, or the choice Cut, is drawn as it is, with nothing
// in between. Ma: the layer follows the view's own redraws — nothing is drawn while nothing moves.
Item {
    id: se
    property Flickable view: null
    property bool horizontal: false
    // Off for a view whose content maps another process's surface over itself (a web page in a panel).
    property bool on: true
    // The zone along each edge, in px: short, so the rest of the view is untouched.
    readonly property real len: view ? (horizontal ? view.width : view.height) : 0
    readonly property real zone: Math.max(8, Math.min(28, len * 0.14))
    readonly property real blurPx: 6
    readonly property string mode: Theme.scrollEdges
    readonly property bool overflows: !!view && (horizontal ? view.contentWidth > view.width + 1 : view.contentHeight > view.height + 1)
    readonly property bool active: on && mode !== "cut" && overflows && view.visible && view.width > 0 && view.height > 0
    // How much is cut beyond each edge, as the zone's share (eased in over the zone: no step at an end).
    readonly property real startCut: !view ? 0 : horizontal ? view.contentX - view.originX : view.contentY - view.originY
    readonly property real endCut: !view ? 0 : horizontal ? view.contentWidth - view.width - (view.contentX - view.originX)
        : view.contentHeight - view.height - (view.contentY - view.originY)
    readonly property real a0: Math.max(0, Math.min(1, startCut / zone))
    readonly property real a1: Math.max(0, Math.min(1, endCut / zone))
    // (what the view holds keeps its still colours while the layer draws it: ColorFlow.holdStill)
    onActiveChanged: if (view) ColorFlow.holdStill(view, active)
    Component.onDestruction: if (view) ColorFlow.holdStill(view, false)

    x: view ? view.x : 0
    y: view ? view.y : 0
    width: view ? view.width : 0
    height: view ? view.height : 0
    z: view ? view.z : 0

    // The view's own layer (not a ShaderEffectSource beside it: a live one drew every change of the view twice — once
    // for the window, once more for its texture — measured on the pinned sidebars while the colour flow ran, 18 frames a
    // second for 9). The effect reads this item's numbers.
    Binding { target: se.view ? se.view.layer : null; property: "enabled"; value: se.active; when: se.view !== null; restoreMode: Binding.RestoreValue }
    Binding { target: se.view ? se.view.layer : null; property: "effect"; value: edgeFx; when: se.view !== null; restoreMode: Binding.RestoreValue }
    Component {
        id: edgeFx
        ShaderEffect {
            property vector4d uEdge: Qt.vector4d(se.a0, se.a1, se.len > 0 ? se.zone / se.len : 0, se.horizontal ? 1 : 0)
            property vector4d uLook: Qt.vector4d(se.len > 0 ? se.blurPx / se.len : 0,
                se.horizontal ? se.width / Math.max(1, se.height) : se.height / Math.max(1, se.width),
                se.mode === "blur" ? 1 : 0, 0.94)
            fragmentShader: Qt.resolvedUrl("../shaders/scroll_edge.frag.qsb")
        }
    }
}
