import QtQuick
import "../core"

// What a bar item needs for its hover preview (I284, I285): the pointer's rest asks the Stage's peek for `source`; a click
// answers it (the peek goes). Fills its parent; takes no button.
Item {
    id: ps
    property string source: ""
    property string output: ""
    property bool enabled_: true
    anchors.fill: parent
    HoverHandler { id: hover }
    TapHandler { acceptedButtons: Qt.LeftButton | Qt.MiddleButton; onTapped: Peeks.dismiss() }
    PeekSource {
        target: ps.parent
        source: ps.enabled_ ? ps.source : ""
        output: ps.output
        hovered: hover.hovered
    }
}
