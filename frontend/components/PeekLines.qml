import QtQuick
import "../core"

// The lines of a peek (K35): the first in the foreground, the rest dim, one fact each. The Stage frames it. A mod's
// Peek.qml is one of these with its facts. A line that does not fit `maxWidth` is cut with an ellipsis, so a long title
// never widens the peek past the output.
Column {
    id: pl
    property var lines: []
    property int maxWidth: 400
    // The inks of the first line and the rest (a look's tooltip ink on its balloon, W53).
    property color fg: Theme.fg
    property color dim: Theme.dim
    spacing: 2

    Repeater {
        model: pl.lines
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            required property var modelData
            required property int index
            text: modelData
            width: Math.min(pl.maxWidth, implicitWidth)
            elide: Text.ElideRight
            color: index === 0 ? pl.fg : pl.dim
            font.pixelSize: index === 0 ? Theme.fs : Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }
    }
}
