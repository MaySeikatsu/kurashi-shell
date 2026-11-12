import QtQuick
import qs.core

// Synced lines in a window of `rows` rows that keeps the current line in its middle (Apple Music, shellseikatsu's
// `LyricsWallpaper.qml`): the current one large and in the foreground colour, the others smaller and dim, fading with
// their distance. The window moves to the next line in `Theme.stdMs` (0 under motion none). A click on a line asks
// `ly.seekTo` (the player decides). Not interactive: it follows the song.
// W75 (B118): the move is stepped by a Timer, not the view's highlight animation. Any animation that starts runs Qt's
// animation driver, and its start draws a frame in every window of the shell (the threaded render loop asks them all):
// on the user's session every window of both outputs committed once a lyric line. A Timer is a pause to Qt — it starts
// no driver — so only this window draws, at the display's rate, for the move.
ListView {
    id: lv
    required property var ly
    property int rows: 3
    property int bigSize: Theme.fsTitle + 2
    property int smallSize: Theme.fs
    property int align: Text.AlignHCenter
    readonly property real rowH: Math.round(bigSize * 1.9)
    // The current line in the middle row (the first lines below an empty top: the margin lets the view stand above 0).
    readonly property real middle: Math.floor(rows / 2) * rowH
    readonly property real targetY: Math.max(0, ly.index) * rowH - middle

    implicitHeight: rows * rowH
    clip: true
    interactive: false
    model: ly.lines
    topMargin: middle
    bottomMargin: middle
    highlightRangeMode: ListView.NoHighlightRange
    highlightFollowsCurrentItem: false
    currentIndex: -1

    property real fromY: 0
    property real movedAt: 0
    function snap() { glide.stop(); contentY = targetY }
    onTargetYChanged: {
        if (Theme.stdMs <= 0 || !visible) { snap(); return }
        fromY = contentY
        movedAt = Date.now()
        glide.start()
    }
    // (a new song resets the view to its top; the window goes back to its line)
    onCountChanged: Qt.callLater(snap)
    onVisibleChanged: if (visible) snap()
    Component.onCompleted: snap()
    Timer {
        id: glide
        interval: 16
        repeat: true
        onTriggered: {
            var t = Math.min(1, (Date.now() - lv.movedAt) / Math.max(1, Theme.stdMs))
            // (the highlight's own curve was a smooth ease in-out)
            var e = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2
            lv.contentY = lv.fromY + (lv.targetY - lv.fromY) * e
            if (t >= 1) stop()
        }
    }
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
