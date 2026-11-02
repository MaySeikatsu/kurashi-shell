import QtQuick

// The layer effect of a masked shape form (ShapeForm.masked; shaders/form_mask.frag): set it as `layer.effect` of the
// item that holds the surface's shape and card, with `layer.enabled` only while the form moves (Ma: no layer at rest).
// The form's numbers are in its frame (y away from the edge the surface comes from): `flipped` for a bottom or right
// edge, `transposed` for a left or right one. `keep`: the frame px drawn whole (a bar's strip, the island's head);
// `cut`: expand's foot cuts what lies past it (where no morph draws the reveal).
ShaderEffect {
    property QtObject form: null
    property real keep: 0
    property bool flipped: false
    property bool transposed: false
    property bool cut: false
    readonly property size size: Qt.size(width, height)
    readonly property vector4d iris: form && form.irisR >= 0 ? Qt.vector4d(form.irisX, form.irisY, form.irisR, 0)
        : Qt.vector4d(0, 0, -1, 0)
    readonly property real flip: flipped ? 1 : 0
    readonly property real axis: transposed ? 1 : 0
    readonly property real below: form ? form.below : 1
    readonly property real reach: cut && form ? form.foot : 1e6
    fragmentShader: Qt.resolvedUrl("../../shaders/form_mask.frag.qsb")
}
