import QtQuick
import "../core"
import "pen.js" as Pen

// PenInk (K62, docs/ux/texture.md "The pen"): the layer effect that draws a block's content — its text and icons — with
// the pen's text modifiers (`Theme.penText*`; shaders/pen_text.frag). Block.qml makes the layer only while some text
// modifier is in effect (`Theme.penText`), so nothing costs anything otherwise. Presentation only: the content's items,
// their input and their accessible names are untouched.
//
// Seed: the pen's per-block salt (components/pen.js `salt`: the block's place in its parent and its parent's place, on
// a 24 px grid; or the block's explicit `penSeed`) moves the noise by up to 1023 px, so two blocks differ. It does not
// depend on where the block's window or card is on the screen: a card sliding in shows the same ink every time it
// opens, and a static block never shimmers. The layer re-renders only when the content changes.
ShaderEffect {
    id: ink
    // The layer's texture (Item.layer names it `source`).
    property variant source
    property Item anchor: null
    property int seed: -1

    readonly property int cellX: anchor ? Pen.cell(anchor.x) : 0
    readonly property int cellY: anchor ? Pen.cell(anchor.y) : 0
    readonly property int salt: { cellX; cellY; return seed >= 0 ? seed : Pen.salt(anchor) }

    // Named as the shader's uniforms (pen_text.frag `buf`).
    readonly property vector4d mods: Qt.vector4d(Theme.penTextPressure, Theme.penTextBreaks, Theme.penTextFade,
        Theme.penTextWobble)
    readonly property vector4d shape: Qt.vector4d(width, height, salt & 1023, (salt >>> 10) & 1023)

    fragmentShader: Qt.resolvedUrl("../shaders/pen_text.frag.qsb")
}
