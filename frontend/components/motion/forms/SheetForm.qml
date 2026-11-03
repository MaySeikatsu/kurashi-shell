import QtQuick
import "../../../core"

// SheetForm (W59.4, K83; docs/ux/motion-engine.md §5 "sheet forms", §10, §11): the base of every sheet form — the whole
// card (fill, material, border, content) captured into one layer while it moves and drawn through a mesh warp. FormHost
// loads a sheet form only while 0 < p < 1 and sets {source, progress, edge, origin, params, size, direction, surface,
// form}; at rest the form and its layer are gone (Ma: no texture, no timer, PSS back to baseline).
//
// What the base gives a form:
//   capture      a ShaderEffectSource of `source` (live, hideSource, at device pixels), the `src` sampler of every pass;
//   canonical    the hinge frame: `a` along the hinge (the card's edge on the bar), `d` away from it, z toward the viewer.
//                `hinge`, `axisA`, `axisD` (item px; unit vectors on screen) and `along` × `away` (the card's size in
//                that frame) — the shaders work in it, so one shader serves a top, bottom, left or right bar;
//   perspective  a fixed focal length (`focal`, px) with its eye over the hinge's middle: a point lifted toward the
//                viewer projects away from that point, never back over the bar (D2: the hinge stays on the bar);
//   light        the K82 light (`Theme.lightDirToken`, toward the light, y down) — the crease shading of every form;
//   tones        `backside` (the back of the paper: the card's fill 8 % darker) and `cover` (a book's cover);
//   handover     `shadowK` (the elevation shadow's weight: out over the first 10 % of a close, in over the last 10 % of
//                an open), `filletK` (the join's fillets: in over the last 15 %), `solidFill` and `blurOff` (a translucent
//                fill draws solid and the blur region leaves while warped) — read by the host (CONTRACT-CHANGE row 656);
//   timing       `sub(p, a, b)` and `ease(s)`, for the per-panel lag of fold, book and crumple.
// The forms clamp p to [0, 1] (no sheet form overshoots: the meta says so) and land exactly flat at 1, so the frame at rest
// is the card itself.
Item {
    id: sheet
    anchors.fill: parent

    // --- from FormHost ---
    property Item source: null
    property real progress: 0
    property string edge: "top"
    property rect origin: Qt.rect(0, 0, 0, 0)
    property var params: ({})
    property size size: Qt.size(width, height)
    property string direction: "open"
    property string surface: "panel"
    property string form: ""

    // --- derived ---
    readonly property real p: Math.max(0, Math.min(1, progress))
    readonly property bool horizontal: edge === "left" || edge === "right"
    // Where the captured card lies in this item (normally the same rect: FormHost's body fills it).
    readonly property rect area: {
        var s = source, w = width, h = height
        if (!s || s.width <= 0 || s.height <= 0) return Qt.rect(0, 0, w, h)
        var o = s.mapToItem(sheet, 0, 0)
        return Qt.rect(o.x, o.y, s.width, s.height)
    }
    readonly property real along: horizontal ? area.height : area.width
    readonly property real away: horizontal ? area.width : area.height
    // The hinge frame in the capture's item px: canonical (a, d) → hinge + a·axisA + d·axisD.
    readonly property point hinge: edge === "bottom" ? Qt.point(0, area.height)
        : edge === "right" ? Qt.point(area.width, 0) : Qt.point(0, 0)
    readonly property point axisA: horizontal ? Qt.point(0, 1) : Qt.point(1, 0)
    readonly property point axisD: edge === "bottom" ? Qt.point(0, -1) : edge === "right" ? Qt.point(-1, 0)
        : edge === "left" ? Qt.point(1, 0) : Qt.point(0, 1)
    // The origin's middle along the hinge (canonical a), clamped into the card; the card's middle without one.
    readonly property real originA: {
        if (origin.width <= 0 && origin.height <= 0) return along / 2
        var cx = origin.x + origin.width / 2 - area.x, cy = origin.y + origin.height / 2 - area.y
        var a = (cx - hinge.x) * axisA.x + (cy - hinge.y) * axisA.y
        return Math.max(0, Math.min(along, a))
    }
    // The eye: over the hinge's middle, `focal` px in front of the screen. Fixed (not per card), so every sheet in the
    // shell recedes alike; long enough that a lifted panel grows by a sixth, not a half.
    property real focal: 1400
    // The eye's place along the hinge (canonical a): the hinge's middle; a form may put it over what stays (fold's anchor).
    property real eyeA: along / 2

    // The K82 light, toward the light (x right, y down, z toward the viewer). A light straight on (a look without one:
    // [0, 0, 1]) would light every tilted panel alike and the folds would not read: then the paper's own studio light,
    // from the top left, as DESIGN-SYSTEM's bevels assume.
    readonly property vector3d light: {
        var t = Theme.lightDirToken
        var v = Qt.vector3d(t && t.length > 0 ? t[0] : 0, t && t.length > 1 ? t[1] : 0, t && t.length > 2 ? t[2] : 1)
        if (Math.hypot(v.x, v.y) < 0.12) v = Qt.vector3d(-0.36, -0.48, 0.8)
        return v.normalized()
    }
    // The card's fill as the paper's colour (a card is the bar's surface, I277): its back is that, 8 % darker; a book's
    // cover takes the accent into it.
    property color fill: Theme.surface
    readonly property color backside: Qt.darker(Qt.rgba(fill.r, fill.g, fill.b, 1), 1.087)
    readonly property color cover: Qt.tint(backside, Qt.alpha(Theme.accent, 0.16))
    // A translucent fill (glass, vibrancy) draws at its solid fallback while warped: the capture's alpha over this one is
    // full (the AA corners keep their fraction). 1 = opaque already.
    property real fillAlpha: Math.max(0.05, Theme.panel.a)
    // How strongly the panels' tilt shades (fold's `crease` param, 0.35 by default).
    property real shade: 0.35

    // --- handover (read by the host: CONTRACT-CHANGE row 656) ---
    // (a form may widen these windows — genie's body pours a long way, so its shadow fades with it, S21)
    property real shadowK: smooth01((p - 0.9) / 0.1)
    property real filletK: smooth01((p - 0.85) / 0.15)
    readonly property bool solidFill: true
    readonly property bool blurOff: true

    // --- timing helpers ---
    function clamp01(x) { return Math.max(0, Math.min(1, x)) }
    function smooth01(x) { var s = clamp01(x); return s * s * (3 - 2 * s) }
    // The fraction of [a, b] that p has crossed.
    function sub(x, a, b) { return b <= a ? (x >= b ? 1 : 0) : clamp01((x - a) / (b - a)) }
    // A panel's own motion: a soft start and a softer landing (smootherstep), on top of the transition's curve.
    function ease(s) { s = clamp01(s); return s * s * s * (s * (s * 6 - 15) + 10) }

    // --- the layer ---
    readonly property real dpr: Window.window && Window.window.screen ? Window.window.screen.devicePixelRatio
        : Screen.devicePixelRatio
    property alias capture: cap
    ShaderEffectSource {
        id: cap
        sourceItem: sheet.source
        hideSource: true
        live: true
        smooth: true
        visible: false
        textureSize: Qt.size(Math.ceil(sheet.area.width * sheet.dpr), Math.ceil(sheet.area.height * sheet.dpr))
    }

    // The uniforms every pass shares (the first vec4s of every sheet shader's block, in this order).
    readonly property vector4d uSize: Qt.vector4d(area.width, area.height, along, away)
    readonly property vector4d uAxes: Qt.vector4d(axisA.x, axisA.y, axisD.x, axisD.y)
    readonly property vector4d uHinge: Qt.vector4d(hinge.x, hinge.y, focal, eyeA)
    readonly property vector4d uLight: Qt.vector4d(light.x, light.y, light.z, shade / 0.35)
    readonly property vector4d uBack: Qt.vector4d(backside.r, backside.g, backside.b, 0.07)
    readonly property vector4d uCover: Qt.vector4d(cover.r, cover.g, cover.b, 0.04)
    readonly property vector4d uMisc: Qt.vector4d(fillAlpha, p, dpr, 0)

    // One mesh pass over the capture: a form names its shaders (`shaders/motion/<name>.{vert,frag}.qsb`) and grid, and
    // adds its own uniforms (u0 … u3) as properties.
    component Pass: ShaderEffect {
        property string name: ""
        property Item host: null
        x: host ? host.area.x : 0
        y: host ? host.area.y : 0
        width: host ? host.area.width : 0
        height: host ? host.area.height : 0
        property var src: host ? host.capture : null
        property vector4d uSize: host ? host.uSize : Qt.vector4d(0, 0, 0, 0)
        property vector4d uAxes: host ? host.uAxes : Qt.vector4d(1, 0, 0, 1)
        property vector4d uHinge: host ? host.uHinge : Qt.vector4d(0, 0, 1400, 0)
        property vector4d uLight: host ? host.uLight : Qt.vector4d(0, 0, 1, 1)
        property vector4d uBack: host ? host.uBack : Qt.vector4d(0, 0, 0, 0)
        property vector4d uCover: host ? host.uCover : Qt.vector4d(0, 0, 0, 0)
        property vector4d uMisc: host ? host.uMisc : Qt.vector4d(1, 0, 1, 0)
        property vector4d u0: Qt.vector4d(0, 0, 0, 0)
        property vector4d u1: Qt.vector4d(0, 0, 0, 0)
        property vector4d u2: Qt.vector4d(0, 0, 0, 0)
        property vector4d u3: Qt.vector4d(0, 0, 0, 0)
        blending: true
        cullMode: ShaderEffect.NoCulling
        vertexShader: name ? Qt.resolvedUrl("../../../shaders/motion/" + name + ".vert.qsb") : ""
        fragmentShader: name ? Qt.resolvedUrl("../../../shaders/motion/" + name + ".frag.qsb") : ""
    }

    // (FormHost sets the form after creation: the line waits for it)
    property bool announced: false
    onFormChanged: if (!announced && form !== "") {
        announced = true
        console.log("motion: sheet layer up " + surface + " " + form)
    }
    Component.onDestruction: if (announced) console.log("motion: sheet layer " + surface + " " + form + " released")
}
