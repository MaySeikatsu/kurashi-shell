import QtQuick
import "../../core"
import "../../core/motion"

// One surface's form per transition (K83, docs/ux/motion-engine.md §5–§7; W59.3): which form it opens or closes in, and
// the one progress that form runs on. The surface says what it wants (`want`: open at rest, or gone) and keeps the rest of
// its machinery; this reads `Theme.motionForm(surface, dir)` when a transition starts from rest and **latches** it, so a
// reversal mid-way continues the form in flight (brief §7) and a token change lands on the next transition. Modes:
//   grow   today's path, untouched: `grow` and the transform forms (slide, zoom, fade, flip, bleed, stepped, rubber; on a
//          morph they are the morph's grow, as before W59), `none`, and any form this surface cannot draw. The Driver
//          is off (it stands at 0 or 1), so nothing here moves;
//   shape  expand, iris, stamp, outline: the Driver runs `p` 0 → 1 (open) or 1 → 0 (close) on the profile's curves, and
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
    // Forms this surface draws as shapes (a surface without a morph may serve fewer).
    property var shapes: ["expand", "iris", "stamp", "outline"]
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
    readonly property bool busy: formed && (drv.running || (p > 0.0001 && p < 0.9999))
    readonly property string direction: drv.direction
    property QtObject shape: null
    readonly property bool masked: shape !== null && busy && shape.masked
    signal landed(real at)

    function modeOf(f) {
        if (shapes.indexOf(f) >= 0) return "shape"
        var m = f !== "" ? Theme.formMeta(f) : null
        if (m && m.family === "sheet" && m.available !== false) return "sheet"
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
    onWantChanged: {
        dir = want ? "open" : "close"
        if (quiet) return
        latch(dir)
        var t = want ? 1 : 0
        if (drv.to !== t) drv.to = t
        else if (drv.value !== t && !drv.running) drv.go()
    }
    // A surface that is already in place when it is made (a toast that budded today's way): wanted, at rest, no form yet.
    function standOpen() {
        quiet = true; want = true; quiet = false
        drv.snap(1)
        drv.to = 1
    }
    // Snap to the wanted end (a retarget hands the shape to the surface's springs; the surface hid).
    function finish() { drv.snap(want ? 1 : 0) }
    // Back to today's path at rest (the surface hid): the next transition latches afresh.
    function reset() {
        drv.snap(want ? 1 : 0)
        if (form !== "") { form = ""; makeShape() }
    }

    property Driver drv: Driver {
        curves: Theme.motionCurves
        role: r.role
        enabled: r.formed
        keepVelocity: true
        onLanded: at => r.landed(at)
    }
    Component.onDestruction: if (shape) shape.destroy()
}
