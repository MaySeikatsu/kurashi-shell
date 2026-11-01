import QtQuick
import Quickshell
import "../core"

// W57 (K78 decision 4, I338): the sheet's shadow into the hole — the frame band and the docked bars cast the key light's
// shadow, short-reached, onto what lies in the window cut into the sheet (the desktop, the windows' edges). The hole is a
// rounded rect in output coordinates (`x0 y0 x1 y1`, `radius`); this window stands at `origin` on its output and owns the
// part `own` of the hole (output coordinates: each hole pixel is painted by exactly one window — no seam, no double
// darkness where the strips meet). Fill the window's content with it (z −1: under the sheet). Analytic, one pass
// (shaders/sheet_shadow.frag); made only while elevation is on; 0 frames at rest (Ma).
//
// The direction is the surfaces' (Theme.elevationDir), or away from a lamp held on the output under follow (Light.heldLamp,
// as Elevation): one vector per window, taken where the hole's edge nearest the window's middle lies.
Loader {
    id: ss
    // The hole, output px.
    property real x0: 0
    property real y0: 0
    property real x1: 0
    property real y1: 0
    property real radius: 0
    // Where this window stands on its output (Light.originOf), and the part of the hole it owns (output px).
    property point origin: Qt.point(0, 0)
    property rect own: Qt.rect(0, 0, 0, 0)
    z: -1
    active: Theme.elevationMode !== "off" && Theme.elevationStrength > 0 && x1 > x0 && y1 > y0 && own.width > 0
        && own.height > 0 && width > 0 && height > 0

    // The key layer of level 1 (the band, docked bars: Elevation.qml's ladder), a touch stronger: it is the only layer.
    readonly property real s: Theme.elevationStrength
    readonly property real dark: Theme.darkScheme ? 1.6 : 1
    readonly property color ink: Qt.rgba(Theme.line.r * 0.4, Theme.line.g * 0.4, Theme.line.b * 0.4, 1)
    readonly property real dist: 4
    readonly property real blur: 10
    readonly property real alpha: 0.24
    // (Theme.sheetReach is the room this needs: distance × the longest length factor + 3 σ.)

    readonly property var qsw: QsWindow.window
    // Where the shadow is taken: the hole's edge nearest this window's middle.
    readonly property point at: {
        var mx = origin.x + width / 2, my = origin.y + height / 2
        return Qt.point(Math.max(x0, Math.min(x1, mx)), Math.max(y0, Math.min(y1, my)))
    }
    readonly property var dir: {
        var h = Light.heldLamp(qsw)
        return h ? Light.awayFrom(h.x, h.y, at.x, at.y, Theme.elevationDir) : Theme.elevationDir
    }

    sourceComponent: ShaderEffect {
        width: ss.width
        height: ss.height
        readonly property vector4d hole: Qt.vector4d(ss.x0 - ss.origin.x, ss.y0 - ss.origin.y, ss.x1 - ss.origin.x, ss.y1 - ss.origin.y)
        readonly property vector4d clipRect: Qt.vector4d(ss.own.x - ss.origin.x, ss.own.y - ss.origin.y,
            ss.own.x + ss.own.width - ss.origin.x, ss.own.y + ss.own.height - ss.origin.y)
        readonly property color color: Qt.rgba(ss.ink.r, ss.ink.g, ss.ink.b, Math.min(0.9, ss.alpha * ss.s * ss.dark))
        readonly property point offset: Qt.point(ss.dir[0] * ss.dist * ss.dir[2] * ss.s, ss.dir[1] * ss.dist * ss.dir[2] * ss.s)
        readonly property size size: Qt.size(width, height)
        readonly property real radius: ss.radius
        readonly property real sigma: ss.blur * Math.max(0.5, ss.s) / 2
        fragmentShader: Qt.resolvedUrl("../shaders/sheet_shadow.frag.qsb")
    }
}
