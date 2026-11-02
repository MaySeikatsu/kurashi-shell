import QtQuick

// zoom (W53.0a): scales up from 0.92 while it fades in.
TransformForm {
    opacity: 1 - away
    sx: 0.92 + 0.08 * (1 - away)
    sy: sx
}
