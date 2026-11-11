import QtQuick
import "../../core"
import "../../core/motion"
import "../../core/motion/curves.js" as C

// One surface's form per transition (K83, docs/ux/motion-engine.md §5–§7; W59.3): which form it opens or closes in, and
// the one progress that form runs on. The surface says what it wants (`want`: open at rest, or gone) and keeps the rest of
// its machinery; this reads `Theme.motionForm(surface, dir)` when a transition starts from rest and **latches** it, so a
// reversal mid-way continues the form in flight (brief §7) and a token change lands on the next transition. Modes:
//   grow   today's path, untouched: `grow` and the transform forms (slide, zoom, fade, flip, bleed, stepped, rubber; on a
//          morph they are the morph's grow, as before W59), `none`, and any form this surface cannot draw. The Driver
//          is off (it stands at 0 or 1), so nothing here moves;
//   shape  expand, iris, stamp, outline, liquid: the Driver runs `p` 0 → 1 (open) or 1 → 0 (close) on the profile's curves, and
//          `shape` (forms/<Form>.qml, a ShapeForm) turns it into the numbers the surface draws its live shape from;
//   sheet  a paper form (W59.4+, `family: sheet`, available): the Driver runs `p` and the surface's card-level FormHost
//          takes it as its progress; the shape stands at rest meanwhile.
// `hold` (the surface's other motion still in flight, e.g. its springs) keeps the latch across a reversal. Ma: the
// Driver runs only while `p` moves; KURASHI_MOTION_SCRUB holds it (shots by progress).
QtObject {
    id: r
    property string surface: "panel"
    property bool want: false
    property bool hold: false
    // The curve role: "auto" (open the opening way, close back) or one role for both ways ("fast": a peek, brief §6).
    property string role: "auto"
    // Forms this surface draws as shapes (a surface without a morph serves fewer: liquid needs the live morph, W59.9a).
    property var shapes: ["expand", "iris", "stamp", "outline", "liquid"]
    // Whether the surface hosts the sheet forms (a card-level FormHost); false: a sheet form keeps today's path (W59.9a: the
    // dock, until it has a host).
    property bool sheets: true
    // Where the user pressed (W59.9a, row 658), in the form's frame; NaN = no press (the origin's centre stands in).
    property real pressX: NaN
    property real pressY: NaN
    // The ShapeForm's inputs (see forms/ShapeForm.qml), bound by the surface.
    property real fromCx: 0
    property real fromW: 0
    property real fromTop: 0
    property real fromFoot: 0
    property real fromR: 0
    property real toCx: 0
    property real toW: 0
    property real toTop: 0
    property real toFoot: 0
    property real toR: 0
    property real edgeY: 0

    property string form: ""
    readonly property string mode: modeOf(form)
    readonly property bool formed: mode !== "grow"
    readonly property bool sheet: mode === "sheet"
    readonly property real p: drv.value
    // Between its ends (held by a scrub counts: the shot is mid-way).
    // (and while a warm start makes the form ahead of its travel, `pending`: the transition has begun for everything
    // that asks — the surface keeps its content, counts as not at rest, holds its other motion)
    readonly property bool busy: formed && (pending || drv.running || (p > 0.0001 && p < 0.9999))
    readonly property string direction: drv.direction
    property QtObject shape: null
    readonly property bool masked: shape !== null && busy && shape.masked
    signal landed(real at)

    function modeOf(f) {
        if (shapes.indexOf(f) >= 0) return "shape"
        var m = f !== "" ? Theme.formMeta(f) : null
        if (sheets && m && m.family === "sheet" && m.available !== false) return "sheet"
        return "grow"
    }
    function pascal(n) { return n.charAt(0).toUpperCase() + n.slice(1) }
    function makeShape() {
        if (shape) { shape.destroy(); shape = null }
        if (mode !== "shape") return
        var c = Qt.createComponent(Qt.resolvedUrl("forms/" + pascal(form) + ".qml"))
        if (c.status !== Component.Ready) {
            console.log("motion: form " + form + " failed to load on " + surface + ": " + c.errorString())
            form = "none"
            return
        }
        var o = c.createObject(r)
        var keys = ["fromCx", "fromW", "fromTop", "fromFoot", "fromR", "toCx", "toW", "toTop", "toFoot", "toR", "edgeY"]
        keys.forEach(function (k) { o[k] = Qt.binding(function () { return r[k] }) })
        o.atX = Qt.binding(function () { return isNaN(r.pressX) ? r.fromCx : r.pressX })
        o.atY = Qt.binding(function () { return isNaN(r.pressY) ? r.fromFoot : r.pressY })
        o.progress = Qt.binding(function () { return r.p })
        o.direction = Qt.binding(function () { return r.direction })
        o.params = Qt.binding(function () { return Theme.formParams(r.form) })
        shape = o
    }
    // A new transition starts from rest: take the form it runs in. Mid-way (this form's or the surface's other motion):
    // keep the one in flight.
    function latch(dir) {
        if (busy || hold) return
        var f = Theme.motionForm(surface, dir)
        if (f === form) return
        form = f
        makeShape()
        // (from rest the Driver stands where the surface stood: open at 1, gone at 0)
        drv.snap(dir === "open" ? 0 : 1)
    }
    property bool quiet: false
    // The way the transition goes, set before it starts — a card-level FormHost's `direction` (bound to the surface's own
    // state it could still read the old way when the form's progress leaves its rest and FormHost latches).
    property string dir: "close"
    // The warm start (B90, session 29; docs/ux/motion-engine.md "Warm start"): a sheet form's first frames were its
    // slowest — the form is made, the surface is drawn into its layer for the first time (every glyph, picture and
    // shader of a window that did not exist a moment ago) — and they fell inside the motion: an opening began with two
    // or three long frames (measured: 70 to 230 ms) and read as a stutter. A surface that says `warm` has its FormHost
    // (`run: <this>`) make the form and take its picture while the progress still stands at its rest — nothing to see
    // when opening, the card itself when closing — and the travel starts on the frame after that picture was shown
    // (FormHost calls `start()`; it gives up after 300 ms, and this after 1.2 s without a host).
    property bool warm: false
    property bool pending: false
    // In motion, or about to be: the shell's colour clock rests meanwhile (core/ColorFlow.qml).
    readonly property bool moving: busy
    onMovingChanged: ColorFlow.rest(moving ? 1 : -1)
    // Whether what the surface joins should already count it as there (a bar leaves its rule out under a joined
    // surface): at rest and through the last part of a form, not while a form has barely begun — the rule was cut over
    // the surface's whole span the moment a form started, a gap in the line before anything stood there (the user,
    // session 29: "the frame outline disappears, before the surface is already spawning there").
    // (A sheet form only: there the surface stands at rest inside the form's picture. A shape form draws the live
    // shape, which hangs from its neighbour's rule in every frame — `test-island-join`: with the rule back at the start
    // of a close it ran on under the folding card.)
    readonly property bool covers: !sheet || (want && !pending && p > 0.9)
    property Timer primeWait: Timer { interval: 1200; onTriggered: if (r.pending) r.start() }
    function start() {
        primeWait.stop()
        var t = want ? 1 : 0
        if (drv.to !== t) drv.to = t
        else if (drv.value !== t && !drv.running) drv.go()
        // (after the travel has begun: `busy` holds the form the wait made, FormHost)
        pending = false
    }
    onWantChanged: {
        dir = want ? "open" : "close"
        if (quiet) return
        var waited = pending
        latch(dir)
        var t = want ? 1 : 0
        // (asked back before the travel began: the surface stands where it is wanted, and is told so)
        if (waited && !drv.running && Math.abs(drv.value - t) < 1e-4) {
            pending = false
            primeWait.stop()
            if (drv.to !== t) drv.to = t
            landed(t)
            return
        }
        if (warm && sheet && !drv.running && Math.abs(drv.value - t) > 0.999) {
            pending = true
            primeWait.restart()
            return
        }
        start()
    }
    // A surface that is already in place when it is made (a toast that budded today's way): wanted, at rest, no form yet.
    function standOpen() {
        pending = false
        primeWait.stop()
        quiet = true; want = true; quiet = false
        drv.snap(1)
        drv.to = 1
    }
    // Snap to the wanted end (a retarget hands the shape to the surface's springs; the surface hid).
    function finish() { pending = false; primeWait.stop(); drv.snap(want ? 1 : 0) }
    // Back to today's path at rest (the surface hid): the next transition latches afresh.
    function reset() {
        pending = false
        primeWait.stop()
        drv.snap(want ? 1 : 0)
        if (form !== "") { form = ""; makeShape() }
    }

    // S21: the latched form's pace (forms meta, `pace`): a sheet form tells a longer story than the profile's curve allows
    // — every role's curve runs that much longer while this form runs (the speed setting is already in the curves).
    readonly property real pace: { var m = form !== "" ? Theme.formMeta(form) : null; return m && m.pace > 0 ? m.pace : 1 }
    // A large surface takes a little longer (the user, session 27: a form that reads well on a card is hurried on a
    // sidebar a screen tall): `extent` is the surface's longer side in px; from 400 px the form runs up to half as long
    // again at 1200 px and more. 0: not said, no stretch.
    property real extent: 0
    readonly property real stretch: extent > 0 ? 1 + 0.5 * Math.max(0, Math.min(1, (extent - 400) / 800)) : 1
    readonly property var pacedCurves: {
        var c = Theme.motionCurves, f = r.pace * r.stretch
        if (f === 1) return c
        return { open: C.stretch(c.open, f), close: C.stretch(c.close, f), fast: C.stretch(c.fast, f),
                 effects: C.stretch(c.effects, f) }
    }
    property Driver drv: Driver {
        curves: r.pacedCurves
        role: r.role
        enabled: r.formed
        keepVelocity: true
        onLanded: at => r.landed(at)
    }
    Component.onDestruction: { if (moving) ColorFlow.rest(-1); if (shape) shape.destroy() }
}
