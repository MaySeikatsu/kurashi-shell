import QtQuick
import "../../core"
import ".."

// A group's block behind a run of a bar (chromes with groups, K42/K45): the run's box plus `Theme.gap` around it, the face
// centred on the bar. Under flat chrome nothing is drawn and nothing moves (the rows keep their places). The soft shadow is
// a short one: the bar's window ends a few px under the block. K67: face and hard shadow are centred together, so a longer
// shadow (strength 2) or one cast upwards stays inside the bar's window; at the defaults (straight down by
// `Theme.shadowDy`) this is where the face always stood.
Block {
    required property Item around
    // (I471d: a scrap of paper is a little longer than what lies on it, so its torn ends have room)
    readonly property real padX: Theme.gap + 2 + (Theme.edgeStyle === "ripped" ? 6 : 0)
    // (`[decor] bar.group = none`: one strip, no block round each group — 98's taskbar; contract row 596.)
    visible: Theme.groups && around.visible && around.width > 0 && Theme.decor("bar.group", "block") !== "none"
    x: around.x - padX
    y: (parent.height - (Theme.barH - 8) - Math.abs(Theme.sinkY)) / 2 - Math.min(0, Theme.sinkY)
    width: around.width + 2 * padX
    height: Theme.barH - 8 + Theme.shadowDy
    radius: Theme.rFull
    ringScale: 0.5
    glowRoom: 3
    paintAlways: true
    // (I471d: under the torn edge a group is a scrap of paper lying on the bar: a tone of its own, so it reads as one
    // sheet; its tear and its short shadow do the rest)
    fill: Theme.edgeStyle === "ripped" ? Theme.containerHigh
        : (Theme.lifted ? Theme.surfaceAlpha : "transparent")
    // (a scrap casts a fuller shadow than a group of the soft chrome: it is what sets it off the bar)
    softScale: Theme.edgeStyle === "ripped" ? 0.55 : 0.3
}
