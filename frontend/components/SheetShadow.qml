import QtQuick
import Quickshell
import "../core"
import "sidebar"

// W57 (K78 decision 4, I338): the sheet's shadow into the hole — the frame band and the docked bars cast the key light's
// shadow, short-reached, onto what lies in the window cut into the sheet (the desktop, the windows' edges). The hole is a
// rounded rect in output coordinates (`x0 y0 x1 y1`, `radius`); this window stands at `origin` on its output and owns the
// part `own` of the hole (output coordinates: each hole pixel is painted by exactly one window — no seam, no double
// darkness where the strips meet). Fill the window's content with it (z −1: under the sheet). Analytic, one pass
// (shaders/sheet_shadow.frag); made only while elevation is on; 0 frames at rest (Ma).
//
// The direction is the surfaces' (Theme.elevationDir), or away from a lamp held on the output under follow (Light.heldLamp,
// as Elevation). One vector per output, taken at the hole's middle: every window of the sheet paints a part of one shadow,
// so a vector of their own (each taken at its own edge) made a step where two of them meet.
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
    active: Theme.sheetMode !== "off" && Theme.elevationStrength > 0 && x1 > x0 && y1 > y0 && own.width > 0
        && own.height > 0 && width > 0 && height > 0

    // I427: a key layer along the light and a faint one all round (the band read as flat with the key alone: one side
    // only, 4 px), or, Inward, one all round, as Caelestia's sheet casts: no direction.
    readonly property real s: Theme.elevationStrength
    readonly property real dark: Theme.darkScheme ? 1.6 : 1
    readonly property color ink: Qt.rgba(Theme.line.r * 0.4, Theme.line.g * 0.4, Theme.line.b * 0.4, 1)
    readonly property bool inward: Theme.sheetMode === "inward"
    readonly property real dist: 6
    readonly property real blur: 10
    readonly property real alpha: 0.36
    readonly property real roundBlur: 18
    readonly property real roundAlpha: inward ? 0.6 : 0.22
    // (Theme.sheetReach is the room this needs: distance × the longest length factor + 3 σ.)

    readonly property var qsw: QsWindow.window
    // Where the shadow is taken: the hole's middle, the same for every window of this hole.
    readonly property point at: Qt.point((x0 + x1) / 2, (y0 + y1) / 2)
    // Under `elevation_pointer` the pointer's lamp turns it too, as it turns the surfaces' (Elevation).
    readonly property bool lamp: Theme.sheetMode === "follow" && Theme.elevationPointer && Light.wanted && !!qsw && !!qsw.screen
        && Light.reaches(qsw.screen.name)
    readonly property var dir: {
        if (lamp) return Light.awayFrom(Light.xOn(qsw.screen.name), Light.yOn(qsw.screen.name), at.x, at.y, Theme.sheetDir)
        var h = Theme.sheetMode === "follow" ? Light.heldLamp(qsw) : null
        return h ? Light.awayFrom(h.x, h.y, at.x, at.y, Theme.sheetDir) : Theme.sheetDir
    }
    // (eased as the surfaces' are: the frame's shadow never jumps when the lamp comes or goes)
    readonly property real wantX: dir[0] * dir[2]
    readonly property real wantY: dir[1] * dir[2]
    property real ux: wantX
    property real uy: wantY
    Behavior on ux { enabled: ss.active && Theme.springOn; NumberAnimation { duration: Theme.longMs; easing.type: Easing.OutCubic } }
    Behavior on uy { enabled: ss.active && Theme.springOn; NumberAnimation { duration: Theme.longMs; easing.type: Easing.OutCubic } }

    // A translucent card standing on the bar (I435): the shadow would show through it.
    readonly property var cardBox: qsw && qsw.screen ? SidebarGeom.cardOf(qsw.screen.name) : null
    component Layer: ShaderEffect {
        property real ox: 0
        property real oy: 0
        property real strength: 0
        property real soft: 0
        width: ss.width
        height: ss.height
        readonly property vector4d hole: Qt.vector4d(ss.x0 - ss.origin.x, ss.y0 - ss.origin.y, ss.x1 - ss.origin.x, ss.y1 - ss.origin.y)
        readonly property vector4d clipRect: Qt.vector4d(ss.own.x - ss.origin.x, ss.own.y - ss.origin.y,
            ss.own.x + ss.own.width - ss.origin.x, ss.own.y + ss.own.height - ss.origin.y)
        readonly property color color: Qt.rgba(ss.ink.r, ss.ink.g, ss.ink.b, Math.min(0.9, strength * ss.s * ss.dark))
        readonly property vector4d cut: ss.cardBox ? Qt.vector4d(ss.cardBox.x - ss.origin.x, ss.cardBox.y - ss.origin.y,
            ss.cardBox.x + ss.cardBox.width - ss.origin.x, ss.cardBox.y + ss.cardBox.height - ss.origin.y) : Qt.vector4d(0, 0, 0, 0)
        readonly property point offset: Qt.point(ox, oy)
        readonly property size size: Qt.size(width, height)
        readonly property real radius: ss.radius
        readonly property real sigma: soft * Math.max(0.5, ss.s) / 2
        fragmentShader: Qt.resolvedUrl("../shaders/sheet_shadow.frag.qsb")
    }
    sourceComponent: Item {
        width: ss.width
        height: ss.height
        Layer { strength: ss.roundAlpha; soft: ss.roundBlur }
        Layer {
            visible: !ss.inward
            strength: ss.alpha
            soft: ss.blur
            ox: ss.ux * ss.dist * ss.s
            oy: ss.uy * ss.dist * ss.s
        }
    }
}
