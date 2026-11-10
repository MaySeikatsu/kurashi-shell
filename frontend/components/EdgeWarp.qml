import QtQuick
import "../core"

// The layer effect of a torn edge (I471d, K121; shaders/edge_warp.frag): set it as `layer.effect` of a surface's face,
// with `layer.enabled: Theme.edgeTorn`. The seed is the surface's own (its size), so no two tears are alike.
ShaderEffect {
    property real depth: Theme.edgeDepth
    readonly property vector4d uSize: Qt.vector4d(width, height, depth, (Math.round(width) * 7 + Math.round(height) * 13) % 97)
    fragmentShader: Qt.resolvedUrl("../shaders/edge_warp.frag.qsb")
}
