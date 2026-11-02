import QtQuick

// The layer effect of a masked shape form (ShapeForm.masked; shaders/form_mask.frag): set it as `layer.effect` of the
// item that holds the surface's shape and card, with `layer.enabled` only while the form moves (Ma: no layer at rest).
// The form's numbers are in its frame (y away from the edge the surface comes from): `flipped` for a bottom or right
// edge, `transposed` for a left or right one. `keep`: the frame px drawn whole (a bar's strip, the island's head);
// `cut`: expand's foot cuts what lies past it (where no morph draws the reveal) — `pad` px further once the form is
// near its rest (W59.9a: what hangs below the card, its shadow, comes in by then, so the landing has no pop).
// `frame`: where the form's frame lies in this item (its corner and size; the item may reach past it, `bleed`).
ShaderEffect {
    property QtObject form: null
    property real keep: 0
    property bool flipped: false
    property bool transposed: false
    property bool cut: false
    property real pad: 0
    property rect frame: Qt.rect(0, 0, width, height)
    readonly property size size: Qt.size(width, height)
    readonly property vector4d iris: form && form.irisR >= 0 ? Qt.vector4d(form.irisX, form.irisY, form.irisR, 0)
        : Qt.vector4d(0, 0, -1, 0)
    readonly property vector4d area: Qt.vector4d(frame.x, frame.y, frame.width, frame.height)
    readonly property real flip: flipped ? 1 : 0
    readonly property real axis: transposed ? 1 : 0
    readonly property real below: form ? form.below : 1
    readonly property real reach: cut && form ? form.foot + pad * form.smooth(0.8, 1, form.progress) : 1e6
    fragmentShader: Qt.resolvedUrl("../../shaders/form_mask.frag.qsb")
}
