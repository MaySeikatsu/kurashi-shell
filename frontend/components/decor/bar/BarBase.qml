import QtQuick
import "../../../core"

// The contract of a bar ground (`[slots] bar`, W53.2): drawn under the bar's groups, filling the bar. `edge` is the screen
// edge the bar stands on ("top", "bottom", "left", "right"): the part lights the side that faces the screen's middle
// (XP's and 7's taskbars have their light line along the top while they stand at the bottom). Reads `[decor] bar.fill`
// (one role solid, two a gradient), `bar.edge` (the light line's role) and `bar.gloss`.
Item {
    property string edge: "top"
    readonly property bool vertical: edge === "left" || edge === "right"
    // The inner edge (towards the screen's middle).
    readonly property string inner: edge === "top" ? "bottom" : edge === "bottom" ? "top" : edge === "left" ? "right" : "left"
}
