import QtQuick
import Quickshell
import "../core"

// Relief (K59, docs/ux/texture.md; the formula in DESIGN-SYSTEM "Texture and light"): the material's relief, lit by the
// light in effect and drawn over whatever lies under this item (a normal "over" blend, premultiplied). The GPU twin of
// `kurashi_texture::shade`; shaders/relief.frag says which line mirrors which.
//
// Registration (the sheet is continuous in output coordinates): the shader takes the fragment's own window pixel and adds
// the window's origin on its output (Light.originOf: the layer's anchors, margins and size, from QsWindow). A block at rest
// therefore shows the part of the sheet that lies where it is on the output, across windows, with no per-item position to
// track. flags.x says whether gl_FragCoord counts rows from the bottom (GL) or the top.
//
// Shape: the sheet fills the item's own rounded rectangle (`radius`, antialiased; `shape` is the item's size).
// Tiles: the window's TileSheet, named as `tileSheet` on its layer window, so every Relief of a window samples one pair of
// textures; a window without one gets a pair of its own. Ma: the owners make no Relief without a shell texture, and the
// pointer lamp is read only in the pointer mode, on the output the pointer is over.
ShaderEffect {
    id: rel

    // The corner radius of this item (logical px).
    property real radius: 0

    // The layer window this item is in: Quickshell's PanelWindow (anchors, margins, screen) through QsWindow, and the
    // Qt window (device pixels) through Window.
    // Quickshell's QsWindow.window does not re-evaluate when the item joins its window; Window.window does, so the
    // layer window is looked up once the item has one.
    readonly property var win: Window.window
    readonly property var qsw: win ? QsWindow.window : null
    readonly property string outName: qsw && qsw.screen ? qsw.screen.name : ""
    readonly property point origin: Light.originOf(qsw)
    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
    // The lamp is this output's only while the pointer light is in use; elsewhere the static light holds.
    readonly property bool lamped: Theme.lightMode === "pointer" && Light.output === outName

    // The tile pair: the window's own, or this item's (made only in a window that names none).
    readonly property bool sharedSheet: !!(qsw && qsw.tileSheet)
    readonly property var tiles: sharedSheet ? qsw.tileSheet : own.item
    Loader {
        id: own
        active: !rel.sharedSheet && Theme.texOn && Theme.texTilePx > 0
        sourceComponent: TileSheet {}
    }
    property variant tileTex: tiles ? tiles.normal : null
    property variant inkTex: tiles ? tiles.ink : null

    // The uniforms below are named as the shader's (relief.frag `buf`): a ShaderEffect binds them by property name.
    readonly property vector4d tileInfo: Qt.vector4d(Theme.texTilePx, Theme.texTileLogical, Theme.texScale, Theme.texAmp)
    readonly property vector4d material: Qt.vector4d(Theme.texGloss, Theme.texShininess, Theme.texInkAlpha, rel.radius)
    readonly property vector4d inkCol: Qt.vector4d(Theme.texInk.r, Theme.texInk.g, Theme.texInk.b, 0)
    readonly property vector4d lightDir: Qt.vector4d(Theme.lightDirToken[0], Theme.lightDirToken[1],
        Theme.lightDirToken[2], 0)
    readonly property vector4d lightCol: Qt.vector4d(Theme.lightColor.r, Theme.lightColor.g, Theme.lightColor.b, 0)
    readonly property vector4d lamp: Qt.vector4d(lamped ? Light.x : 0, lamped ? Light.y : 0,
        Theme.lightHeight, lamped ? Light.k : 0)
    readonly property vector4d sheet: Qt.vector4d(origin.x, origin.y, dpr, (win ? win.height : 0) * dpr)
    // `win` in the expression: the graphics API is known only once the item is in a window.
    readonly property vector4d flags: Qt.vector4d(
        win && (GraphicsInfo.api === GraphicsInfo.OpenGL || GraphicsInfo.api === GraphicsInfo.OpenGLRhi) ? 1 : 0, 0, 0, 0)
    readonly property vector4d shape: Qt.vector4d(width, height, 0, 0)

    fragmentShader: Qt.resolvedUrl("../shaders/relief.frag.qsb")
    blending: true
}
