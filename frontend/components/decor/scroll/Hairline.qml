import QtQuick
import "../../../core"

// Hairline (W53.5, docs/ux/styles.md §8): the PS2 dashboard's scroll mark — a silver hairline track, faint, and the thumb a
// slim bar of tower blue (light at rest, full while held or under the pointer). No arrows. Roles only (rule 4); static.
ScrollBase {
    id: sb
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property bool vert: orientation === Qt.Vertical
    readonly property real len: vert ? height : width
    readonly property real thumbLen: Math.max(16, len * Math.min(1, size))
    readonly property real thumbAt: Math.max(0, Math.min(len - thumbLen, len * position))
    Rectangle {
        visible: sb.size < 1
        x: sb.vert ? Math.round((sb.width - sb.hair) / 2) : 0
        y: sb.vert ? 0 : Math.round((sb.height - sb.hair) / 2)
        width: sb.vert ? sb.hair : sb.width
        height: sb.vert ? sb.height : sb.hair
        color: Qt.alpha(Theme.fg, 0.22)
    }
    Rectangle {
        visible: sb.size < 1
        readonly property real t: 3
        x: sb.vert ? Math.round((sb.width - t) / 2) : Math.round(sb.thumbAt)
        y: sb.vert ? Math.round(sb.thumbAt) : Math.round((sb.height - t) / 2)
        width: sb.vert ? t : Math.round(sb.thumbLen)
        height: sb.vert ? Math.round(sb.thumbLen) : t
        radius: t / 2
        color: Qt.alpha(Theme.accent, sb.pressed || sb.hovered ? 1 : 0.7)
    }
}
