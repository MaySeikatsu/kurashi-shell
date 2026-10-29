import QtQuick
import Quickshell
import "../core"

// Relief (K59, K61; docs/ux/texture.md; the formula in DESIGN-SYSTEM "Texture and light"): the material's relief, lit by
// the light in effect and drawn over whatever lies under this item (a normal "over" blend, premultiplied). The GPU twin
// of `kurashi_texture::shade_at`; shaders/relief.frag says which line mirrors which.
//
// Registration (the sheet is continuous in output coordinates): the shader takes the fragment's own window pixel and adds
// the window's origin on its output (Light.originOf: the layer's anchors, margins and size, from QsWindow). A block at rest
// therefore shows the part of the sheet that lies where it is on the output, across windows, with no per-item position to
// track. uFlags.x says whether gl_FragCoord counts rows from the bottom (GL) or the top.
//
// The sheet on moving surfaces (K61, `texture.sheet`):
// - carried (default): a surface that slides or grows takes its sheet along. Its owner publishes how far it is from its
//   place at rest as `sheetCarry` (a point, logical px, output axes) on its layer window, beside `tileSheet`; every
//   Relief of the window reads it (`carry`; an owner whose item moves on its own, a swiped card or the island's shape,
//   sets `carry` itself, from `windowCarry`). The shader samples the sheet at (output position − carry): the material
//   moves with the surface, and at rest the carry is 0, so the surface lies exactly on the continuous sheet. The light
//   stays where it is (taken at the output position). Only translation is carried, not a scale.
// - fixed: K59's still sheet (no carry).
// - separate: every Relief its own sheet from its own top-left corner (no continuity across surfaces).
// `bandEdge` / `bandWeight`: above `bandEdge` (item px) the carry does not apply and the relief is weighed by
// `bandWeight` — the island's head, which stays registered with the bar it sits in (and, over a translucent strip whose
// own relief shows through, is shaded about once, not twice).
//
// Shape: the sheet fills the item's own rounded rectangle (`radius` or per corner, antialiased), and, given a `mask`, only
// where the mask's alpha is: cover × mask.a (I168, generic). `mask` is any texture provider laid over exactly this item's
// rectangle (qt_TexCoord0 samples it): a ShaderEffectSource of a shape's fill (the island: the MorphShape's `fillPath`
// drawn in white, redrawn with scheduleUpdate() only when the path changes), or of an icon or glyph on a transparent face
// (row 285: the relief then lies on the icon's own pixels and never halos its ground). Keep such a source `live: false`
// and update it when its content changes (Ma), and park it outside the window or hide its source (`hideSource`).
// Pictures never get the relief (I167): the ones registered with Light in this window are cut out (four at most), placed
// once per frame the window draws anyway (afterAnimating), never on an idle window.
// Tiles: the window's TileSheet, named as `tileSheet` on its layer window, so every Relief of a window samples one set of
// textures; a window without one gets a set of its own. Ma: the owners make no Relief without a shell texture, the
// pointer lamp and the spotlight's aim are read only in their modes, on the output the pointer is over, and the height
// map is sampled only while relief shadows are on.
ShaderEffect {
    id: rel

    // The corner radius of this item (logical px), or per corner (as Rectangle: −1 = `radius`).
    property real radius: 0
    property real topLeftRadius: -1
    property real topRightRadius: -1
    property real bottomRightRadius: -1
    property real bottomLeftRadius: -1
    // A texture provider whose alpha clips the relief (over this item's rectangle), or null.
    property var mask: null
    // See the header (carried sheet).
    property point carry: windowCarry
    property real bandEdge: -1e9
    property real bandWeight: 1

    // The layer window this item is in: Quickshell's PanelWindow (anchors, margins, screen) through QsWindow, and the
    // Qt window (device pixels) through Window.
    // Quickshell's QsWindow.window does not re-evaluate when the item joins its window; Window.window does, so the
    // layer window is looked up once the item has one.
    readonly property var win: Window.window
    readonly property var qsw: win ? QsWindow.window : null
    readonly property string outName: qsw && qsw.screen ? qsw.screen.name : ""
    readonly property point origin: Light.originOf(qsw)
    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
    readonly property point windowCarry: qsw && qsw.sheetCarry !== undefined ? qsw.sheetCarry : Qt.point(0, 0)
    readonly property real outW: qsw && qsw.screen ? qsw.screen.width : 0
    readonly property real outH: qsw && qsw.screen ? qsw.screen.height : 0
    // The lamp is this output's only while the pointer light or the spotlight is in use; elsewhere it rests.
    readonly property bool pointed: Light.output === outName && Light.k > 0
        && (Theme.lightMode === "pointer" || Theme.lightMode === "spotlight")

    // The tile set: the window's own, or this item's (made only in a window that names none).
    readonly property bool sharedSheet: !!(qsw && qsw.tileSheet)
    readonly property var tiles: sharedSheet ? qsw.tileSheet : own.item
    Loader {
        id: own
        active: !rel.sharedSheet && Theme.texOn && Theme.texTilePx > 0
        sourceComponent: TileSheet {}
    }
    property variant tileTex: tiles ? tiles.normal : null
    property variant inkTex: tiles ? tiles.ink : null
    // Unused samplers get the tile (never sampled: their flags are off).
    readonly property bool shadowed: Theme.texShadow > 0 && !!tiles && !!tiles.heightMap
    property variant heightTex: shadowed ? tiles.heightMap : tileTex
    property variant maskTex: mask ? mask : tileTex

    // The uniforms below are named as the shader's (relief.frag `buf`, all `u…`, so no owner's id is shadowed by them
    // inside a `Relief { }` block): a ShaderEffect binds them by property name.
    readonly property vector4d uTile: Qt.vector4d(Theme.texTilePx, Theme.texTileLogical, Theme.texScale, Theme.texAmp)
    readonly property vector4d uMaterial: Qt.vector4d(Theme.texGloss, Theme.texShininess, Theme.texInkAlpha, 0)
    readonly property vector4d uRadii: Qt.vector4d(topLeftRadius < 0 ? radius : topLeftRadius,
        topRightRadius < 0 ? radius : topRightRadius, bottomRightRadius < 0 ? radius : bottomRightRadius,
        bottomLeftRadius < 0 ? radius : bottomLeftRadius)
    // W56 (I288): under squircle corners the box's corner is the superellipse through the shapes' cubic's midpoint
    // ((3k + 4) / 8 of the corner on each axis, k the handle ratio): 2^(-1/n) = (3k + 4) / 8.
    readonly property vector4d uSquircle: Qt.vector4d(Theme.squircle > 0
        ? -Math.LN2 / Math.log((3 * Math.min(0.99, Math.max(0.56, Theme.squircle)) + 4) / 8) : 0, 0, 0, 0)
    readonly property vector4d uInk: Qt.vector4d(Theme.texInk.r, Theme.texInk.g, Theme.texInk.b, 0)
    readonly property vector4d uLightDir: Qt.vector4d(Theme.lightDirToken[0], Theme.lightDirToken[1],
        Theme.lightDirToken[2], 0)
    readonly property vector4d uLightCol: Qt.vector4d(Theme.lightColor.r, Theme.lightColor.g, Theme.lightColor.b, 0)
    // A lamp held at fractions of the output: the wallpaper's light (`light.lamp`, K59) or the spotlight's pin (K61).
    readonly property var held: Theme.lightMode === "wallpaper" ? Theme.tok("light.lamp", null)
        : (Theme.lightMode === "spotlight" ? Theme.lightPin : null)
    readonly property bool pinned: !!held && held.length === 2 && outW > 0
    readonly property vector4d uLamp: pinned
        ? Qt.vector4d(held[0] * outW, held[1] * outH, Theme.lightHeight, 1)
        : (Theme.lightMode === "pointer" && pointed
            ? Qt.vector4d(Light.x, Light.y, Theme.lightHeight, Light.k) : Qt.vector4d(0, 0, Theme.lightHeight, 0))
    // The spotlight's aim: the pointer over this output's shell surfaces, gliding back to the middle (Light.k).
    readonly property bool beamed: Theme.lightMode === "spotlight" && pinned
    readonly property real beamRad: Math.max(1, Math.min(89, Theme.lightBeam)) * Math.PI / 180
    readonly property vector4d uBeam: Qt.vector4d(
        outW / 2 + (pointed ? (Light.x - outW / 2) * Light.k : 0),
        outH / 2 + (pointed ? (Light.y - outH / 2) * Light.k : 0),
        Math.cos(beamRad), Math.cos(beamRad / 2))
    readonly property vector4d uSheet: Qt.vector4d(origin.x, origin.y, dpr, (win ? win.height : 0) * dpr)
    readonly property vector4d uSize: Qt.vector4d(width, height, 0, 0)
    // `win` in the expression: the graphics API is known only once the item is in a window.
    readonly property vector4d uFlags: Qt.vector4d(
        win && (GraphicsInfo.api === GraphicsInfo.OpenGL || GraphicsInfo.api === GraphicsInfo.OpenGLRhi) ? 1 : 0,
        beamed ? 1 : 0, Theme.texSheet === "separate" ? 1 : 0, mask ? 1 : 0)
    readonly property vector4d uRelief: Qt.vector4d(shadowed ? Theme.texShadow : 0, Theme.texReliefPx, Theme.texDepth,
        Theme.texLit)
    readonly property vector4d uCarry: Theme.texSheet === "carried" ? Qt.vector4d(carry.x, carry.y, 0, 0)
        : Qt.vector4d(0, 0, 0, 0)
    readonly property vector4d uBand: Qt.vector4d(bandEdge, bandWeight, 0, 0)

    // The pictures of this window (I167), cut out of the relief where they lie over it.
    readonly property var pictures: {
        var l = Light.pictures, out = []
        for (var i = 0; i < l.length; i++) if (l[i].win === win) out.push(l[i].item)
        return out
    }
    property vector4d uHole0: Qt.vector4d(0, 0, 0, 0)
    property vector4d uHole1: Qt.vector4d(0, 0, 0, 0)
    property vector4d uHole2: Qt.vector4d(0, 0, 0, 0)
    property vector4d uHole3: Qt.vector4d(0, 0, 0, 0)
    property vector4d uHoleR: Qt.vector4d(0, 0, 0, 0)
    function placeHoles() {
        var h = [Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0), Qt.vector4d(0, 0, 0, 0)]
        var r = [0, 0, 0, 0], n = 0
        for (var i = 0; i < pictures.length && n < 4; i++) {
            var it = pictures[i]
            if (!it || !it.visible || it.width <= 0 || it.height <= 0) continue
            var o = it.mapToItem(rel, 0, 0)
            if (o.x >= width || o.y >= height || o.x + it.width <= 0 || o.y + it.height <= 0) continue
            h[n] = Qt.vector4d(o.x, o.y, it.width, it.height)
            r[n] = it.radius !== undefined ? it.radius : 0
            n++
        }
        var hr = Qt.vector4d(r[0], r[1], r[2], r[3])
        if (!uHole0.fuzzyEquals(h[0], 0.01)) uHole0 = h[0]
        if (!uHole1.fuzzyEquals(h[1], 0.01)) uHole1 = h[1]
        if (!uHole2.fuzzyEquals(h[2], 0.01)) uHole2 = h[2]
        if (!uHole3.fuzzyEquals(h[3], 0.01)) uHole3 = h[3]
        if (!uHoleR.fuzzyEquals(hr, 0.01)) uHoleR = hr
    }
    onPicturesChanged: placeHoles()
    onWidthChanged: if (pictures.length > 0) placeHoles()
    onHeightChanged: if (pictures.length > 0) placeHoles()
    Connections {
        target: rel.pictures.length > 0 ? rel.win : null
        function onAfterAnimating() { rel.placeHoles() }
    }

    fragmentShader: Qt.resolvedUrl("../shaders/relief.frag.qsb")
    blending: true
}
