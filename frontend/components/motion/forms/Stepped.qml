import QtQuick

// stepped (W53.5): grows out of its middle, vertically, in the staircase's held steps (a 16-bit RPG window: Final
// Fantasy VI opens its box strip pair by strip pair from the centre) — between steps a scaled frame, at rest exactly
// the pixel grid. The steps are the curve's (`steps(n)`, the daemon's staircase), not the form's.
TransformForm {
    sy: Math.max(0.001, 1 - away)
}
