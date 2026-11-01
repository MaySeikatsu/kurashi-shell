import QtQuick
import "../../../core"
import "../.."

// Keycap (W53.7, docs/ux/styles.md §9 sekai, K42): a scroll bar as a key in a groove — the track a slot cut in the card
// (the highest container, a thin ink outline, fully round), the thumb a small key (Block, keycap chrome: ink outline,
// ring, hard shadow) that sinks onto its shadow while held and takes the accent under the pointer. No arrows. Roles only
// (rule 4); static.
ScrollBase {
    id: sb
    readonly property bool vert: orientation === Qt.Vertical
    readonly property real len: vert ? height : width
    readonly property real thick: vert ? width : height
    readonly property real thumbLen: Math.max(thick * 2, len * Math.min(1, size))
    readonly property real thumbAt: Math.max(0, Math.min(len - thumbLen, len * position))
    Rectangle {
        visible: sb.size < 1
        x: sb.vert ? Math.round(sb.thick * 0.25) : 0
        y: sb.vert ? 0 : Math.round(sb.thick * 0.25)
        width: sb.vert ? Math.round(sb.thick * 0.5) : sb.len
        height: sb.vert ? sb.len : Math.round(sb.thick * 0.5)
        radius: Math.min(width, height) / 2
        color: Theme.color("color.surface_container_highest", "#e0e0ea")
        border.width: Math.max(1, Theme.outlineW - 1)
        border.color: Qt.alpha(Theme.line, 0.6)
    }
    Block {
        visible: sb.size < 1
        x: sb.vert ? 0 : sb.thumbAt
        y: sb.vert ? sb.thumbAt : 0
        width: sb.vert ? sb.thick : sb.thumbLen
        height: sb.vert ? sb.thumbLen : sb.thick
        radius: sb.thick / 2
        pressed: sb.pressed
        fill: sb.hovered || sb.pressed ? Theme.accent : Theme.ring
        penSeed: 0x5E7C
    }
}
