import QtQuick
import "../../core"
import "papercache.js" as PaperCache

// Washi paper (look washi, W29): a very fine fibre grain and a soft inner hairline in the ink colour (`Theme.fg`, low
// alpha), a stronger grain on a surface's ground (the lock, the greeter). The grain is one small tile — an SVG made once
// per ink colour from a fixed seed, so every block shows the same sheet — that Qt's image cache shares between all
// blocks; it tiles seamlessly (a fibre that crosses an edge is drawn again on the other side) and never animates.
// Small blocks (bar groups, keys) get it fainter: more on a 20 px key reads as dirt. Tokens only (rule 4).
FrameBase {
    id: f
    // The ground is paper: the surface's colour under a stronger grain (it replaces the chrome's ruled ground).
    grounds: true

    // The ink without its alpha, so one tile serves every opacity (the layers set theirs).
    readonly property color ink: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 1)
    readonly property string fine: PaperCache.tile(f.ink, 160, 60, 80, 7, 16)
    readonly property string coarse: f.ground ? PaperCache.tile(f.ink, 256, 70, 0, 23, 46) : ""

    // ---- a block: the grain inside the corners' curve, and a soft inner hairline (the sheet's edge) ----
    Image {
        visible: !f.ground && f.fine !== ""
        anchors.fill: parent
        // Clear of the rounded corners (r·(1 − 1/√2)), so no grain shows outside the block.
        anchors.margins: Math.ceil(f.radius * 0.3)
        source: f.fine
        sourceSize: Qt.size(160, 160)
        fillMode: Image.Tile
        smooth: false
        opacity: f.small ? 0.07 : 0.11
    }
    Rectangle {
        visible: !f.ground
        anchors.fill: parent
        anchors.margins: 1.5
        radius: Math.max(0, f.radius - 1.5)
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(f.ink, f.small ? 0.07 : 0.1)
    }

    // ---- the ground: the surface's paper, the fine grain and longer fibres over it ----
    Rectangle {
        visible: f.ground
        anchors.fill: parent
        color: Theme.surface
    }
    Image {
        visible: f.ground
        anchors.fill: parent
        source: f.ground ? f.fine : ""
        sourceSize: Qt.size(160, 160)
        fillMode: Image.Tile
        smooth: false
        opacity: 0.14
    }
    Image {
        visible: f.ground
        anchors.fill: parent
        source: f.coarse
        sourceSize: Qt.size(256, 256)
        fillMode: Image.Tile
        opacity: 0.1
    }
}
