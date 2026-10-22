import QtQuick
import Quickshell
import "../core"

// PenInk (K62, docs/ux/texture.md "The pen"): the layer effect that draws a block's content — its text and icons — with
// the pen's text modifiers (`Theme.penText*`; shaders/pen_text.frag). Block.qml makes the layer only while some text
// modifier is in effect (`Theme.penText`), so nothing costs anything otherwise. Presentation only: the content's items,
// their input and their accessible names are untouched.
//
// Seed: the block's place on its output (the window's origin, Light.originOf, plus the item's place in its window),
// read when the layer is made and when its size changes — not bound per frame, so a block that moves keeps its ink,
// and a static one never shimmers. The layer re-renders only when the content changes.
ShaderEffect {
    id: ink
    // The layer's texture (Item.layer names it `source`).
    property variant source

    readonly property var win: Window.window
    readonly property var qsw: win ? QsWindow.window : null
    property point place: Qt.point(0, 0)
    function locate() {
        var o = Light.originOf(qsw)
        var p = ink.mapToItem(null, 0, 0)
        ink.place = Qt.point(Math.round(o.x + p.x), Math.round(o.y + p.y))
    }
    Component.onCompleted: locate()
    onWidthChanged: locate()
    onHeightChanged: locate()
    onQswChanged: locate()

    // Named as the shader's uniforms (pen_text.frag `buf`).
    readonly property vector4d mods: Qt.vector4d(Theme.penTextPressure, Theme.penTextBreaks, Theme.penTextFade,
        Theme.penTextWobble)
    readonly property vector4d shape: Qt.vector4d(width, height, place.x, place.y)

    fragmentShader: Qt.resolvedUrl("../shaders/pen_text.frag.qsb")
}
