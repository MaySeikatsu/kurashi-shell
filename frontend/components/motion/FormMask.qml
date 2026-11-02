import QtQuick

// The layer effect of a masked shape form (iris, stamp, outline; ShapeForm.masked): set it as `layer.effect` of the item
// that holds the surface's shape and card, with `layer.enabled` only while the form moves (Ma: no layer at rest).
// `keep`: the px from the bar's side drawn whole (the bar's strip, the island's head); `flipped`: the bar is at the
// bottom (the form's frame is a top bar's). The mask itself is analytic (shaders/form_mask.frag).
ShaderEffect {
    property QtObject form: null
    property real keep: 0
    property bool flipped: false
    readonly property size size: Qt.size(width, height)
    readonly property vector4d iris: form && form.irisR >= 0 ? Qt.vector4d(form.irisX, form.irisY, form.irisR, 0)
        : Qt.vector4d(0, 0, -1, 0)
    readonly property real flip: flipped ? 1 : 0
    readonly property real below: form ? form.below : 1
    fragmentShader: Qt.resolvedUrl("../../shaders/form_mask.frag.qsb")
}
