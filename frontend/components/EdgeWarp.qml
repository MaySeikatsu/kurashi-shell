import QtQuick
import "../core"

// The layer effect of a torn edge (I471d, K121; shaders/edge_warp.frag): set it as `layer.effect` of a surface's face,
// with `layer.enabled: Theme.edgeTorn`. The seed is the surface's own (its size), so no two tears are alike.
ShaderEffect {
    property real depth: Theme.edgeDepth
    // The tear's own seed, drawn once (things of one size side by side — a dock's icons — are each torn differently).
    readonly property int seed0: Math.floor(Math.random() * 97)
    // A thing that is small but stands by itself as a sheet (a bar's group): torn in bays as a card is, less deep.
    property bool bold: false
    // The face's own fill, when its owner knows it: the white core then lies on the fill alone, not on text or icons.
    property color fillHint: "transparent"
    readonly property vector4d uFill: Qt.vector4d(fillHint.r, fillHint.g, fillHint.b, fillHint.a > 0 ? 1 : 0)
    readonly property vector4d uSize: Qt.vector4d(width, height, depth, seed0)
    readonly property vector4d uMode: Qt.vector4d(Theme.edgeStyle === "painted" ? 1 : 0, Theme.edgeUneven, bold ? 1 : 0, 0)
    // Which of the layer's own borders are edges of the shape (left, top, right, bottom): all, for a face that fills its
    // layer; a side joined to a bar or lying on the screen's edge is not.
    property vector4d sides: Qt.vector4d(1, 1, 1, 1)
    readonly property vector4d uSides: sides
    fragmentShader: Qt.resolvedUrl("../shaders/edge_warp.frag.qsb")
}
