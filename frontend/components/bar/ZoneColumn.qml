import QtQuick
import "../../core"

// One zone of a side bar as a column of pieces, `Theme.pad` apart (a stretch of tight modules is one piece, `Theme.gap`
// apart): the start zone from the top, the center zone in the middle. Pieces with nothing present take no room.
Column {
    id: zc
    required property var owner
    // [{tight, entries: [entry, …]}, …]
    property var pieces: []
    // Where the window list's room ends (the next zone's top, in this column's parent).
    property real roomEnd: 0
    spacing: Theme.pad
    // B48: what the pieces after piece `i` take (their heights and gaps): the window list's room ends before them, not at
    // the next zone (it ran under them). Read from the later pieces only, so the list's own height is not in it.
    function tailAfter(i) {
        var t = 0
        for (var k = i + 1; k < pieceRep.count; k++) {
            var p = pieceRep.itemAt(k)
            if (p && p.presentN > 0) t += zc.spacing + p.height
        }
        return t
    }
    Repeater {
        id: pieceRep
        model: zc.pieces
        delegate: Column {
            id: piece
            required property var modelData
            required property int index
            property int presentN: 0
            function recount() {
                var n = 0
                for (var i = 0; i < hostRep.count; i++) { var h = hostRep.itemAt(i); if (h && h.present) n++ }
                if (n !== presentN) presentN = n
            }
            visible: presentN > 0
            anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
            spacing: modelData.tight ? zc.owner.tightSpacing : Theme.pad
            Repeater {
                id: hostRep
                model: piece.modelData.entries
                onItemAdded: Qt.callLater(piece.recount)
                onItemRemoved: Qt.callLater(piece.recount)
                delegate: ZoneHost {
                    required property var modelData
                    owner: zc.owner
                    entry: modelData
                    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
                    room: zc.roomEnd - (zc.y + piece.y) - Theme.gap - zc.tailAfter(piece.index)
                    onPresentChanged: piece.recount()
                }
            }
        }
    }
}
