import QtQuick

// PROTOTYPE (session 27, I471 b/d; shaders/edge_fill.frag): a box's fill whose edge is torn ("ripped") or a watercolour
// stroke's ("paint"). Reaches `pad` px past its box on every side. Drawn once: a ShaderEffect with no animated uniform
// repaints only when its box or colour changes (Ma).
ShaderEffect {
    property real radius: 0
    property color fill: "white"
    property string mode: "ripped"
    property real pad: 8
    // A box's own seed, so no two edges are alike: from where and how big it is.
    readonly property real seed: (Math.round(width) * 7 + Math.round(height) * 13) % 97
    readonly property vector4d uBox: Qt.vector4d(width, height, radius, pad)
    readonly property vector4d uColor: Qt.vector4d(fill.r, fill.g, fill.b, fill.a)
    readonly property vector4d uMode: Qt.vector4d(mode === "paint" ? 2 : 1, seed, height > width * 1.3 ? 1 : 0, 0)
    fragmentShader: Qt.resolvedUrl("../shaders/edge_fill.frag.qsb")
}
