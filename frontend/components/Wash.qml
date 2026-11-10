import QtQuick
import Quickshell
import "../core"

// Wash (I460, session 26 prototype): the chrome's colour as one continuous sheet (shaders/wash.frag). A ground puts one
// over its fill with the fill's shape (`radius`, per corner, or a `mask`); every wash on every window samples the same
// canvas — this output, or all outputs as one (Theme.washSpan) — so neighbouring grounds continue each other. Registration
// is Relief's (Light.originOf). Made only while the wash is on (Theme.washOn): no item, no frames otherwise (Ma).
ShaderEffect {
    id: wash

    property real radius: 0
    property real topLeftRadius: -1
    property real topRightRadius: -1
    property real bottomRightRadius: -1
    property real bottomLeftRadius: -1
    property var mask: null
    // The ground's own fill: its step from the surface (a card a little lighter) is kept over the wash.
    property color fill: Theme.surface
    // How much of the wash covers the fill (the ground's own alpha under Translucent).
    property real strength: 1

    readonly property var win: Window.window
    readonly property var qsw: win ? QsWindow.window : null
    readonly property var scr: qsw && qsw.screen ? qsw.screen : null
    readonly property point origin: Light.originOf(qsw)
    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1

    // The canvas: this output alone, or the bounding box of every output (logical px) with this output's place in it.
    readonly property rect canvas: {
        if (!scr) return Qt.rect(0, 0, 1, 1)
        if (Theme.washSpan !== "all" || Theme.washMode === "wallpaper") return Qt.rect(0, 0, scr.width, scr.height)
        var l = Quickshell.screens, x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
        for (var i = 0; i < l.length; i++) {
            x0 = Math.min(x0, l[i].x); y0 = Math.min(y0, l[i].y)
            x1 = Math.max(x1, l[i].x + l[i].width); y1 = Math.max(y1, l[i].y + l[i].height)
        }
        return Qt.rect(scr.x - x0, scr.y - y0, x1 - x0, y1 - y0)
    }

    readonly property vector4d uSheet: Qt.vector4d(origin.x, origin.y, dpr, (win ? win.height : 0) * dpr)
    readonly property vector4d uCanvas: Qt.vector4d(canvas.x, canvas.y, canvas.width, canvas.height)
    readonly property vector4d uFlags: Qt.vector4d(
        win && (GraphicsInfo.api === GraphicsInfo.OpenGL || GraphicsInfo.api === GraphicsInfo.OpenGLRhi) ? 1 : 0,
        0, 0, mask ? 1 : 0)
    // (session 28, colour flow: the shader moves the gradient by the one clock's phase; still, both are 0)
    readonly property vector4d uSize: Qt.vector4d(width, height, strength, ColorFlow.patternIndex > 0 ? ColorFlow.phase : 0)
    readonly property vector4d uRadii: Qt.vector4d(topLeftRadius < 0 ? radius : topLeftRadius,
        topRightRadius < 0 ? radius : topRightRadius, bottomRightRadius < 0 ? radius : bottomRightRadius,
        bottomLeftRadius < 0 ? radius : bottomLeftRadius)
    readonly property vector4d uMode: Qt.vector4d(Theme.washMode === "radial" ? 1 : (Theme.washMode === "watercolour" ? 2
            : (fromWall ? (wall.status === Image.Ready ? 3 : 0) : 0)),
        Theme.washAngle, Theme.washScale, Theme.washSoftness)
    readonly property vector4d uCenter: Qt.vector4d(Theme.washCenter.x, Theme.washCenter.y, Theme.washReach, ColorFlow.patternIndex)
    readonly property var stops: Theme.washStops
    readonly property vector4d uCount: Qt.vector4d(stops.length, fill.r - Theme.surface.r, fill.g - Theme.surface.g,
        fill.b - Theme.surface.b)
    function stop(i) {
        var c = stops[Math.min(i, stops.length - 1)] || Theme.surface
        return Qt.vector4d(c.r, c.g, c.b, 1)
    }
    readonly property vector4d uStop0: stop(0)
    readonly property vector4d uStop1: stop(1)
    readonly property vector4d uStop2: stop(2)
    readonly property vector4d uStop3: stop(3)
    // Pattern "wallpaper" (session 26): the picture under each spot, from the wallpaper mod's document (the output's own
    // picture and how the backend fits it). Watched only in that pattern (Ma); the picture is loaded small — softness
    // picks how small, so the colours blur into each other — and shared by every Wash of the output (the pixmap cache
    // keys on url and size).
    readonly property bool fromWall: Theme.washMode === "wallpaper"
    Watch { doc: "mod.wallpaper"; active: wash.fromWall }
    readonly property var wallOut: {
        if (!fromWall || !scr) return null
        var d = Store.docs ? Store.docs["mod.wallpaper"] : null
        return d && d.outputs ? (d.outputs[scr.name] || null) : null
    }
    readonly property string wallPath: wallOut && wallOut.path ? wallOut.path
        : ((Store.docs && Store.docs["mod.wallpaper"] && Store.docs["mod.wallpaper"].theme
            && Store.docs["mod.wallpaper"].theme.image) || "")
    Image {
        id: wall
        visible: false
        asynchronous: true
        cache: true
        smooth: true
        source: wash.fromWall && wash.wallPath !== "" ? "file://" + wash.wallPath : ""
        readonly property int side: Math.round(160 - 136 * Theme.washSoftness)
        sourceSize: Qt.size(side, side)
    }
    // Cover ("crop"): the picture scaled to fill the output, centred; the rest of the fits stretch for now.
    readonly property vector4d uWall: {
        var iw = wall.implicitWidth, ih = wall.implicitHeight
        var ow = canvas.width, oh = canvas.height
        if (!fromWall || iw <= 0 || ih <= 0 || ow <= 0 || oh <= 0) return Qt.vector4d(1, 1, 0, 0)
        var ia = iw / ih, oa = ow / oh
        if (ia > oa) { var sx = oa / ia; return Qt.vector4d(sx, 1, (1 - sx) / 2, 0) }
        var sy = ia / oa
        return Qt.vector4d(1, sy, 0, (1 - sy) / 2)
    }
    // The text's side and the ground's luminance limit for 4.5:1 with it (WCAG: (Lt + .05) / (Lg + .05) >= 4.5).
    readonly property real inkY: 0.2126 * lin(Theme.fg.r) + 0.7152 * lin(Theme.fg.g) + 0.0722 * lin(Theme.fg.b)
    function lin(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4) }
    readonly property vector4d uInk: inkY > 0.5 ? Qt.vector4d(1, (inkY + 0.05) / 4.6 - 0.05, 0, 0)
        : Qt.vector4d(0, 4.6 * (inkY + 0.05) - 0.05, 0, 0)
    property variant wallTex: fromWall && wall.status === Image.Ready ? wall : none

    // Unused sampler: a 1 px source (never sampled: uFlags.w is 0).
    property variant maskTex: mask ? mask : none
    ShaderEffectSource { id: none; width: 0; height: 0; live: false; sourceItem: Rectangle { width: 1; height: 1 } }

    fragmentShader: Qt.resolvedUrl("../shaders/wash.frag.qsb")
    blending: true
}
