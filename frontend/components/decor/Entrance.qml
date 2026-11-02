import QtQuick
import "../motion"

// Entrance (W53.0a, K80; K83): the form a surface's content arrives and leaves in — now the motion engine's FormHost
// (components/motion/FormHost.qml), kept under its old name for the surfaces that wrap their content in it. A surface
// drives `progress` (0 gone … 1 in place) with its own timed animation; the form comes from the tokens per `surface` (the
// look's `motion.style` before W59.1): grow, slide, stepped, zoom, fade, bleed, flip, none (docs/ux/styles.md "Motion
// kinds"; the forms themselves are components/motion/forms/). What the old Entrance offered its callers stays:
// `form`, `slides` (slide and rubber travel by their size), `away` (clamped distance from in place), `travel`
// (unclamped, for an overshoot), `horizontal`.
FormHost {
    readonly property bool horizontal: edge === "left" || edge === "right"
    readonly property real away: 1 - Math.max(0, Math.min(1, progress))
    readonly property bool slides: form === "slide" || form === "rubber"
    readonly property real travel: 1 - progress
}
