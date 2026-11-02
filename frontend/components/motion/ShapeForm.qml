import QtQuick

// The base of a shape form (K83, docs/ux/motion-engine.md §5 "Shape forms"; W59.3): what one progress does to a surface
// that keeps its live vector shape — the join to the bar, the neck, the elevation, the carried material and the blur
// region follow every frame (MorphShape, or a plain card) — so a form yields only numbers its surface draws from.
// Geometry is in a top bar's frame (y grows away from the bar's screen edge; a surface on a bottom bar mirrors it) and,
// along the bar, in the surface's own px. Nothing runs here: the surface's Driver moves `progress` (Ma).
// Inputs:
//   progress   0 gone … 1 at rest (past 1 while the curve overshoots; a form whose meta says `overshoot: false` clamps)
//   from*      the origin (brief §7: the pressed module's box, the pill, else the bar's centre): its centre along the
//              bar, width, top, foot (the line the shape hangs from) and corner radius
//   to*        the card at rest: its centre, width, top, foot and corner radius
//   edgeY      the bar's inner edge — the hinge: what lies before it (the bar's strip, the island's head) stays drawn
//   params     `motion.form_params.<form>`
// Outputs. At p = 1 every output is the card's own, so the frame at rest is exactly the motion-off frame:
//   cx w foot  the silhouette's centre, width and foot
//   grow       how far the body has come out of its origin, 0..1 (where a joined body's top stands)
//   tint       how far fill, head fill, corners and ring are the card's, 0..1
//   sx sy      a scale of the silhouette and the card about (cx, edgeY)
//   masked     the surface draws through a mask while it moves: past `edgeY`, `below` alpha everywhere, or, with `irisR`
//              ≥ 0, only inside the circle (irisX, irisY, irisR); the bar's strip before `edgeY` stays whole
//   content    the card's content (its view), 0..1
//   clipsContent  the content is cut to the silhouette (false: it is drawn whole, transformed with the card)
//   outline    outline rects drawn instead of the shape: `rects` = [{x, y, w, h, r, a}] in the same frame
//   lift       the elevation one level up, 0 at rest … 1 (the shadow tightens as the card lands)
QtObject {
    property real progress: 1
    property string direction: "open"
    property var params: ({})
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

    readonly property real pc: Math.max(0, Math.min(1, progress))
    readonly property bool moving: progress < 1
    function lerp(a, b, t) { return a + (b - a) * t }
    function clamp01(v) { return Math.max(0, Math.min(1, v)) }
    function smooth(a, b, v) { var t = clamp01((v - a) / Math.max(1e-6, b - a)); return t * t * (3 - 2 * t) }

    property real cx: toCx
    property real w: toW
    property real foot: toFoot
    property real grow: 1
    property real tint: 1
    property real sx: 1
    property real sy: 1
    property bool masked: false
    property real below: 1
    property real irisX: 0
    property real irisY: 0
    property real irisR: -1
    property real content: 1
    property bool clipsContent: true
    property bool outline: false
    property var rects: []
    property real lift: 0
}
