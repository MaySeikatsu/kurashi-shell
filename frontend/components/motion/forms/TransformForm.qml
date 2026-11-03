import QtQuick

// The base of a transform form (W53.0a's Entrance forms, K83): what progress does to the whole surface, as plain values
// FormHost binds its own opacity, Translate, Scale, Rotation and (bleed) blur layer to — no layer, nothing runs while
// progress rests. A form sets only the outputs it changes; the rest stay identity. `host` is the FormHost (given at
// creation): its `progress` (0 gone … 1 in place; past 1 while a curve overshoots), `edge` ("top" "bottom" "left"
// "right": where the surface comes from), `width`, `height`.
QtObject {
    property Item host: null
    // Inputs, derived once for every form.
    readonly property real progress: host ? host.progress : 1
    readonly property string edge: host ? host.edge : "top"
    readonly property real w: host ? host.width : 0
    readonly property real h: host ? host.height : 0
    readonly property bool horizontal: edge === "left" || edge === "right"
    // How far from in place, clamped (fades, turns), and unclamped (a slide follows an overshoot past 1).
    readonly property real away: 1 - Math.max(0, Math.min(1, progress))
    readonly property real travel: 1 - progress
    // Outputs.
    property real opacity: 1
    property real tx: 0
    property real ty: 0
    // Scale about the centre.
    property real sx: 1
    property real sy: 1
    // Rotation about (rx, ry) on the axis (ax, ay, 0).
    property real angle: 0
    property real rx: w / 2
    property real ry: h / 2
    property real ax: 0
    property real ay: 1
    // A blur over the surface, 0..1 of FormHost's blurMax; `layered` makes the layer (only while it shows).
    property real blur: 0
    property bool layered: false
}
