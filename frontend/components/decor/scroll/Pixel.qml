import QtQuick
import "../../../core"
import ".."

// Pixel (W53.5, docs/ux/styles.md §7): a 16-bit RPG list's scroll marks on the pixel grid — a track one grid pixel wide in
// the window's dim ink, the thumb a white block two grid pixels wide in a dark outline, and with `[decor] scroll.arrows`
// the lists' ▲ and ▼ (whole grid pixels, white with a dark outline) at the ends, which scroll a line (`step`; repeating
// while held, the timer only then). Roles only (rule 4); static otherwise.
ScrollBase {
    id: sb
    readonly property int g: Math.max(1, Theme.grid(Screen.height) || 2)
    readonly property bool vert: orientation === Qt.Vertical
    readonly property bool arrows: Theme.decor("scroll.arrows", false) === true
    readonly property int btn: arrows ? 5 * g : 0
    readonly property real track: Math.max(0, (vert ? height : width) - 2 * btn)
    readonly property real thumbLen: Math.max(4 * g, Math.round(track * Math.min(1, size) / g) * g)
    readonly property real thumbAt: btn + Math.round(Math.max(0, Math.min(track - thumbLen, track * position)) / g) * g
    readonly property color ink: Theme.color("color.ring", "#f8f8f8")
    readonly property color dark: Theme.color("color.line", "#000000")

    Rectangle {
        visible: sb.size < 1
        x: sb.vert ? Math.round((sb.width - sb.g) / 2 / sb.g) * sb.g : sb.btn
        y: sb.vert ? sb.btn : Math.round((sb.height - sb.g) / 2 / sb.g) * sb.g
        width: sb.vert ? sb.g : sb.track
        height: sb.vert ? sb.track : sb.g
        antialiasing: false
        color: Theme.color("color.outline", "#a8b0d0")
    }
    Rectangle {
        visible: sb.size < 1
        x: sb.vert ? Math.round((sb.width - 4 * sb.g) / 2 / sb.g) * sb.g : sb.thumbAt
        y: sb.vert ? sb.thumbAt : Math.round((sb.height - 4 * sb.g) / 2 / sb.g) * sb.g
        width: sb.vert ? 4 * sb.g : sb.thumbLen
        height: sb.vert ? sb.thumbLen : 4 * sb.g
        antialiasing: false
        color: sb.ink
        border.width: sb.g
        border.color: sb.dark
    }
    component Arrow: Item {
        id: ar
        property int dir: -1
        width: sb.vert ? sb.width : sb.btn
        height: sb.vert ? sb.btn : sb.height
        PixelArt {
            anchors.centerIn: parent
            px: sb.g
            rotation: sb.vert ? (ar.dir < 0 ? 0 : 180) : (ar.dir < 0 ? 270 : 90)
            inks: ({ "#": sb.dark, "w": sb.ink })
            rows: ["..#..", ".#w#.", "#www#", "#####"]
        }
        MouseArea {
            id: hit
            anchors.fill: parent
            onPressed: { sb.step(ar.dir); rep.start() }
            onReleased: rep.stop()
            onCanceled: rep.stop()
        }
        Timer { id: rep; interval: 80; repeat: true; triggeredOnStart: false; onTriggered: sb.step(ar.dir) }
    }
    Arrow { visible: sb.arrows; dir: -1 }
    Arrow {
        visible: sb.arrows
        dir: 1
        x: sb.vert ? 0 : sb.width - width
        y: sb.vert ? sb.height - height : 0
    }
}
