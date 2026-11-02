import QtQuick

// The joined card's rest while a sheet form warps its body (K83, W59.9a; docs/ux/motion-engine.md §5 "the hinge stays
// joined", D2). A surface whose card is joined to its bar keeps drawing its card at rest the whole time a sheet form runs
// (its shape at the rest geometry, the content in it) in one item, `draw`, which this takes into one layer (`texture`,
// window-aligned, so every relief in it stays registered with the output) and hides. The sheet form captures the body's box
// below the hinge from that layer (a `SheetRest.Body` in the surface's FormHost source, clipped to `body`: square where it
// meets the bar), and this draws the rest of it: the bar's side of the hinge (the head, the rule the card hangs from, the
// neck) exactly as at rest, and what lies beside or below the body (the join's fillets, which the surface grows back over
// the landing, the hard shadow) × `k`. So the captured card's fillets are the surface's own outside the capture, and p = 1
// is the rest frame with nothing changing at the swap. One layer, only while `on` (Ma).
// Put it beside `draw` in the same frame (item px, the window's); `body` is the body's box, `hingeY` the hinge's line,
// `barAbove` whether the bar lies at smaller y (a top bar; false for a bottom bar).
ShaderEffect {
    id: sr
    property Item draw: null
    property bool on: false
    property rect body: Qt.rect(0, 0, 0, 0)
    property real hingeY: 0
    property bool barAbove: true
    property real k: 1
    visible: on
    readonly property size size: Qt.size(width, height)
    readonly property vector4d hole: Qt.vector4d(body.x, body.y, body.x + body.width, body.y + body.height)
    readonly property vector4d hinge: Qt.vector4d(hingeY, barAbove ? 1 : -1, k, 0)
    readonly property alias texture: tex
    property var source: tex
    ShaderEffectSource {
        id: tex
        sourceItem: sr.on ? sr.draw : null
        live: true
        hideSource: true
        visible: false
        width: sr.width
        height: sr.height
    }
    fragmentShader: Qt.resolvedUrl("../../shaders/sheet_rest.frag.qsb")

    // The body's part of the layer, for the sheet form's capture: put it in the FormHost's source item (which stands at
    // `body`, clipped), with `rest` this SheetRest; it lays the layer under it so the body's pixels land where they are.
    component Body: ShaderEffect {
        property Item rest: null
        visible: rest !== null && rest.on
        x: rest ? rest.x - parent.x : 0
        y: rest ? rest.y - parent.y : 0
        width: rest ? rest.width : 0
        height: rest ? rest.height : 0
        property var source: rest ? rest.texture : null
    }
}
