import QtQuick
import "../../../core"
import ".."

// Hand (W53.5, docs/ux/styles.md §7): a 16-bit RPG menu row — no band: the selected row has the hand cursor pointing at
// it from the row's lead (`[decor] menu.lead`, the room the caller keeps at the row's start), an original white glove in
// whole grid pixels with a dark outline and grey shading. The cursor jumps: each row draws it while it is the selected one,
// so moving the selection moves it at once (no slide, no easing). A separator is a gap (`menu.separator = space`).
// Roles only (rule 4); static.
MenuRowBase {
    id: row
    readonly property int g: Math.max(1, Theme.grid(Screen.height) || 2)
    PixelArt {
        visible: row.highlighted && row.enabled && !row.separator
        px: row.g
        x: Math.max(0, Math.round((Theme.decor("menu.lead", 0) - width) / 2 / row.g) * row.g)
        anchors.verticalCenter: parent.verticalCenter
        inks: ({ "#": Theme.color("color.line", "#000000"), "w": Theme.color("color.ring", "#f8f8f8"),
                 "g": Theme.color("color.outline", "#a8b0d0") })
        rows: [
            "...####.........",
            "..#wwww########.",
            ".#wwwwwwwwwwwww#",
            ".#wwwww########.",
            ".#wwwgww#.......",
            ".#wwwwg#........",
            ".#wwgww#........",
            "..#wwg#.........",
            "...###.........."
        ]
    }
}
