import QtQuick

// slide (W53.0a; rubber too, on its overshooting curve): the surface travels in from `edge` by its own size, following
// an overshoot past 1.
TransformForm {
    tx: horizontal ? (edge === "left" ? -1 : 1) * w * travel : 0
    ty: horizontal ? 0 : (edge === "top" ? -1 : 1) * h * travel
}
