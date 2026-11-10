import QtQuick
import "../core"

// The layer effect of a torn edge (I471d, K121; shaders/edge_warp.frag): set it as `layer.effect` of a surface's face,
// with `layer.enabled: Theme.edgeTorn`. The seed is the surface's own (its size), so no two tears are alike.
ShaderEffect {
    property real depth: Theme.edgeDepth
    readonly property vector4d uSize: Qt.vector4d(width, height, depth, (Math.round(width) * 7 + Math.round(height) * 13) % 97)
    readonly property vector4d uMode: Qt.vector4d(Theme.edgeStyle === "painted" ? 1 : 0, Theme.edgeUneven, 0, 0)
    // Which of the layer's own borders are edges of the shape (left, top, right, bottom): all, for a face that fills its
    // layer; a side joined to a bar or lying on the screen's edge is not.
    property vector4d sides: Qt.vector4d(1, 1, 1, 1)
    readonly property vector4d uSides: sides
    fragmentShader: Qt.resolvedUrl("../shaders/edge_warp.frag.qsb")
}
