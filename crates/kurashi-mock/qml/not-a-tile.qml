import QtQuick

// A quick.tiles contribution that is not a QuickTile (the mock's test case, W18): the grid gives it a cell and clips it
// to the cell, so its own 360 x 140 block overflows the cell and is cut at the cell's edge; the grid never grows for it.
// It declares the three objects ModLoader hands in, as every contribution does.
Item {
    required property var store
    required property var theme
    required property var i18n
    Rectangle {
        x: 0
        y: 0
        width: 360
        height: 140
        radius: 12
        color: "#2d6a4f"
        Text {
            x: 12
            y: 16
            color: "#ffffff"
            font.pixelSize: 14
            text: "NOT A TILE"
        }
    }
}
