import QtQuick
import "../core"

// The lines of a peek (K35): the first in the foreground, the rest dim, one fact each. The Stage frames it. A mod's
// Peek.qml is one of these with its facts. A line that does not fit `maxWidth` is cut with an ellipsis, so a long title
// never widens the peek past the output.
Column {
    id: pl
    property var lines: []
    property int maxWidth: 400
    spacing: 2

    Repeater {
        model: pl.lines
        Text {
            required property var modelData
            required property int index
            text: modelData
            width: Math.min(pl.maxWidth, implicitWidth)
            elide: Text.ElideRight
            color: index === 0 ? Theme.fg : Theme.dim
            font.pixelSize: index === 0 ? Theme.fs : Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }
    }
}
