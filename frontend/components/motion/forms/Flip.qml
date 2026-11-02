import QtQuick

// flip (W53.0a): turns in about the axis along `edge`, as a card flips, with a fade.
TransformForm {
    opacity: 1 - away
    rx: edge === "right" ? w : (edge === "left" ? 0 : w / 2)
    ry: edge === "bottom" ? h : (edge === "top" ? 0 : h / 2)
    ax: horizontal ? 0 : 1
    ay: horizontal ? 1 : 0
    angle: 90 * away * (edge === "top" || edge === "right" ? -1 : 1)
}
