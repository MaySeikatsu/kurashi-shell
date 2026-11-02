import QtQuick

// bleed (W53.7, washi): fades in while a blur clears, as ink settles into paper. The blur's layer exists only while the
// surface moves.
TransformForm {
    opacity: 1 - away
    layered: away > 0.001
    blur: Math.min(1, away * 1.4)
}
