import QtQuick
import "../../../core"
import ".."

// Hand (W53.5, docs/ux/styles.md §7): a 16-bit RPG menu row — no band: the selected row has the hand cursor pointing at
// it from the row's lead (`[decor] menu.lead`, the room the caller keeps at the row's start). An original white glove,
// 16 × 12 grid pixels as Final Fantasy VI's is 16 × 16 (measured on the FF wiki's FFVI_SNES_Menu.png: outline #181828,
// white, two cool greys; its tip 4 px left of the text), with a dark outline (`line`) and two greys (`outline`,
// `outline_variant`). The cursor jumps: each row draws it while it is the selected one, so moving the selection moves it at
// once (no slide, no easing). A separator is a gap (`menu.separator = space`). Roles only (rule 4); static.
MenuRowBase {
    id: row
    readonly property int g: Math.max(1, Theme.grid(Screen.height) || 2)
    // Made only on the selected row (a menu of 30 rows builds one hand, not 30).
    Loader {
        active: row.highlighted && row.enabled && !row.separator
        anchors.fill: parent
        sourceComponent: PixelArt {
            px: row.g
            x: Math.max(0, Math.round((Theme.decor("menu.lead", 0) * Theme.pixelScale - width) / 2 / row.g) * row.g)
            anchors.verticalCenter: parent.verticalCenter
            inks: ({ "#": Theme.color("color.line", "#000000"), "w": Theme.color("color.ring", "#f8f8f8"),
                     "g": Theme.color("color.outline", "#b8b8b8"), "d": Theme.color("color.outline_variant", "#606868") })
            rows: [
                "....####........",
                "...#wwww#######.",
                "..#wwwwwwwwwwww#",
                ".#wwwwwwgggggg#.",
                ".#wwwww#######..",
                ".#wwwwwwg#......",
                ".#wwwgww#.......",
                ".#wwwwgg#.......",
                ".#wwgwwd#.......",
                "..#wwggd#.......",
                "...#ddd#........",
                "....###........."
            ]
        }
    }
}
