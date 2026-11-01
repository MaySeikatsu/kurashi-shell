import QtQuick
import "../../../core"

// Track (W53.8, docs/ux/styles.md "terminal"): a text-mode scroll bar, `│█│` — a channel one character cell wide between
// two box-drawing strokes, the thumb a run of full blocks (█) in the text's ink, its ends on whole character rows as a
// TUI draws it (the thumb jumps a row at a time); with `[decor] scroll.arrows` a ▲ and a ▼ cell at the ends that step the
// view a row (no dead button: ScrollBase.step). Horizontal bars turn it on its side. Roles only (rule 4); static.
ScrollBase {
    id: sb
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property bool vert: orientation === Qt.Vertical
    readonly property bool arrows: Theme.decor("scroll.arrows", false) === true
    // One character row (vertical) or column (horizontal) of the body face.
    readonly property real cell: Math.max(4, vert ? Math.round(fm.height) : Math.round(fm.averageCharacterWidth))
    readonly property real end: arrows ? cell : 0
    readonly property real len: (vert ? height : width) - 2 * end
    readonly property int rows: Math.max(1, Math.floor(len / cell))
    readonly property int thumbRows: Math.max(1, Math.min(rows, Math.round(rows * Math.min(1, size))))
    readonly property int thumbRow: Math.max(0, Math.min(rows - thumbRows, Math.round(rows * position)))
    FontMetrics { id: fm; font.family: Theme.families[0]; font.pixelSize: Theme.fs }

    // The channel's two strokes.
    Rectangle {
        x: 0; y: 0
        width: sb.vert ? sb.hair : sb.width
        height: sb.vert ? sb.height : sb.hair
        color: Theme.outline
    }
    Rectangle {
        x: sb.vert ? sb.width - sb.hair : 0
        y: sb.vert ? 0 : sb.height - sb.hair
        width: sb.vert ? sb.hair : sb.width
        height: sb.vert ? sb.height : sb.hair
        color: Theme.outline
    }
    // The thumb: whole rows of █.
    Rectangle {
        antialiasing: false
        x: sb.vert ? 2 * sb.hair : sb.end + sb.thumbRow * sb.cell
        y: sb.vert ? sb.end + sb.thumbRow * sb.cell : 2 * sb.hair
        width: sb.vert ? sb.width - 4 * sb.hair : sb.thumbRows * sb.cell
        height: sb.vert ? sb.thumbRows * sb.cell : sb.height - 4 * sb.hair
        color: sb.pressed ? Theme.accent : Qt.alpha(Theme.fg, sb.hovered ? 0.9 : 0.7)
    }
    Repeater {
        model: sb.arrows ? 2 : 0
        Item {
            required property int index
            x: sb.vert ? 0 : (index === 0 ? 0 : sb.width - sb.end)
            y: sb.vert ? (index === 0 ? 0 : sb.height - sb.end) : 0
            width: sb.vert ? sb.width : sb.end
            height: sb.vert ? sb.end : sb.height
            Text {
                anchors.centerIn: parent
                text: sb.vert ? (parent.index === 0 ? "▲" : "▼") : (parent.index === 0 ? "◀" : "▶")
                color: Theme.fg
                font.family: Theme.families[0]
                font.pixelSize: Math.max(8, Theme.fs - 3)
            }
            MouseArea {
                anchors.fill: parent
                onClicked: sb.step(parent.index === 0 ? -1 : 1)
            }
        }
    }
}
