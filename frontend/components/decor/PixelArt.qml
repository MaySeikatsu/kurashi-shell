import QtQuick

// PixelArt (W53.5): a small picture drawn from rows of characters on a grid of `px` logical px — each run of one
// character one Rectangle without antialiasing (no Canvas: a handful of rectangles, painted once). `inks` maps a
// character to a colour; a character it does not name is empty. For pixel-grid parts (snes's hand cursor, marks).
Item {
    id: pa
    property var rows: []
    property var inks: ({})
    property real px: 2
    implicitWidth: (rows.length ? rows[0].length : 0) * px
    implicitHeight: rows.length * px
    readonly property var runs: {
        var out = []
        for (var y = 0; y < rows.length; y++) {
            var r = rows[y], x = 0
            while (x < r.length) {
                var c = r.charAt(x), e = x
                while (e < r.length && r.charAt(e) === c) e++
                if (inks[c] !== undefined) out.push({ x: x, y: y, w: e - x, c: c })
                x = e
            }
        }
        return out
    }
    Repeater {
        model: pa.runs
        Rectangle {
            required property var modelData
            x: modelData.x * pa.px
            y: modelData.y * pa.px
            width: modelData.w * pa.px
            height: pa.px
            antialiasing: false
            color: pa.inks[modelData.c]
        }
    }
}
