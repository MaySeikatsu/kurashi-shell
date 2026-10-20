import QtQuick
import qs.core

// Synced lines in a window of `rows` rows that keeps the current line in its middle (Apple Music, shellseikatsu's
// `LyricsWallpaper.qml`): the current one large and in the foreground colour, the others smaller and dim, fading with
// their distance. The window moves to the next line in `Theme.stdMs` (0 under motion none). A click on a line asks
// `ly.seekTo` (the player decides). Not interactive: it follows the song.
ListView {
    id: lv
    required property var ly
    property int rows: 3
    property int bigSize: Theme.fsTitle + 2
    property int smallSize: Theme.fs
    property int align: Text.AlignHCenter
    readonly property real rowH: Math.round(bigSize * 1.9)

    implicitHeight: rows * rowH
    clip: true
    interactive: false
    model: ly.lines
    currentIndex: Math.max(0, ly.index)
    highlightRangeMode: ListView.StrictlyEnforceRange
    preferredHighlightBegin: Math.floor(rows / 2) * rowH
    preferredHighlightEnd: preferredHighlightBegin + rowH
    highlightMoveDuration: Theme.stdMs
    highlightMoveVelocity: -1
    highlightFollowsCurrentItem: true
    Accessible.role: Accessible.StaticText
    Accessible.name: I18n.tr("mod-lyrics.a11y.line").replace("{line}", lv.ly.currentText !== "" ? lv.ly.currentText
        : I18n.tr("mod-lyrics.a11y.pause"))

    delegate: Item {
        id: row
        required property var modelData
        required property int index
        readonly property bool current: index === lv.ly.index
        readonly property int dist: Math.abs(index - Math.max(0, lv.ly.index))
        width: lv.width
        height: lv.rowH
        Text {
            anchors.fill: parent
            anchors.leftMargin: Theme.xs
            anchors.rightMargin: Theme.xs
            horizontalAlignment: lv.align
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: row.modelData.text !== "" ? row.modelData.text : "♪"
            color: row.current ? Theme.fg : Theme.dim
            opacity: row.current ? 1 : Math.max(0.35, 0.85 - 0.25 * row.dist)
            font.pixelSize: row.current ? lv.bigSize : lv.smallSize
            font.weight: row.current ? Theme.wBold : Theme.wRegular
            font.family: Theme.fam(text, Theme.families)
        }
        MouseArea {
            anchors.fill: parent
            enabled: lv.ly.canSeek
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: lv.ly.seekTo(row.index)
        }
    }
}
