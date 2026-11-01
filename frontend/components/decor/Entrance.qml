import QtQuick
import "../../core"

// Entrance (W53.0a, K80; docs/ux/styles.md "Motion kinds"): the form a surface arrives and leaves in, as the look says
// (`Theme.motionStyle`, data — rule 4). A surface wraps its content in one and drives `progress` (0 gone … 1 in place)
// with its own timed animation on `Theme.openCurve`/`closeCurve` — so the look's curves (a stepped staircase, a rubber
// band's overshoot) shape every form:
//   grow     K74's: the surface grows out of its edge itself; the wrapper leaves the content alone;
//   slide    the content travels in from `edge` by its own size (rubber slides too, on its curve);
//   stepped  W53.5: grows out of its middle, vertically, in the staircase's held steps (a 16-bit RPG window: Final
//            Fantasy VI opens its box strip pair by strip pair from the centre) — between steps a scaled frame, at rest
//            exactly the pixel grid;
//   zoom     scales up from 0.92 while it fades in;
//   fade     fades only;
//   flip     turns in about the axis along `edge`, as a card flips (with a fade);
//   none     motion off (reduce motion): no form at all.
// Nothing runs while `progress` rests (0 frames idle); the transforms are plain properties, no layer.
Item {
    id: en
    property real progress: 1
    // Where the surface comes from: "top", "bottom", "left" or "right" (its edge).
    property string edge: "top"
    readonly property string form: Theme.motionStyle
    readonly property bool horizontal: edge === "left" || edge === "right"
    readonly property real away: 1 - Math.max(0, Math.min(1, progress))
    readonly property bool slides: form === "slide" || form === "rubber"
    // Overshoot (rubber) may carry progress past 1: the slide follows it, the fade does not.
    readonly property real travel: 1 - progress
    opacity: form === "zoom" || form === "fade" || form === "flip" ? 1 - away : 1
    transform: [
        Translate {
            x: en.slides && en.horizontal ? (en.edge === "left" ? -1 : 1) * en.width * en.travel : 0
            y: en.slides && !en.horizontal ? (en.edge === "top" ? -1 : 1) * en.height * en.travel : 0
        },
        Scale {
            origin.x: en.width / 2
            origin.y: en.height / 2
            xScale: en.form === "zoom" ? 0.92 + 0.08 * (1 - en.away) : 1
            yScale: en.form === "stepped" ? Math.max(0.001, 1 - en.away) : xScale
        },
        Rotation {
            origin.x: en.edge === "right" ? en.width : (en.edge === "left" ? 0 : en.width / 2)
            origin.y: en.edge === "bottom" ? en.height : (en.edge === "top" ? 0 : en.height / 2)
            axis { x: en.horizontal ? 0 : 1; y: en.horizontal ? 1 : 0; z: 0 }
            angle: en.form === "flip" ? 90 * en.away * (en.edge === "top" || en.edge === "right" ? -1 : 1) : 0
        }
    ]
}
