import QtQuick

// A box of the dock's surface, placed by its edge (dock.qml). `a0`..`a1` is its distance from the screen edge, across
// the strip; `l0`..`l1` its span along the edge. Both are in the surface's own pixels. The mapping is the one thing that
// differs per edge, so every part of the dock is written once and placed here (WebCard's margins, mirrored per edge).
Item {
    id: box
    property string edge: "right"
    property real surfW: 0           // the surface's size (dock.qml)
    property real surfH: 0
    property real a0: 0
    property real a1: 0
    property real l0: 0
    property real l1: 0

    readonly property bool sideways: edge === "left" || edge === "right"

    x: sideways ? (edge === "right" ? surfW - a1 : a0) : l0
    y: sideways ? l0 : (edge === "bottom" ? surfH - a1 : a0)
    width: sideways ? a1 - a0 : l1 - l0
    height: sideways ? l1 - l0 : a1 - a0
}
