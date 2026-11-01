import QtQuick
import "../../../core"
import "../.."
import ".."

// Pixel (W53.6): a pixel-art caption — Needy Streamer Overload's pastel desktop windows (docs/ux/styles.md §9.1, measured
// on the game's Steam screenshots at 2 px per art pixel: a flat 26 px pink band, the title in violet pixel type after a
// 16 px icon, three square outlined buttons 20 × 20 on a 24 px pitch at the end). Drawn from the look's `[decor]` alone
// (rule 4): the band `title.fill` (`title.fill_inactive` — grey — without focus) with `title.radius` corners cut in steps
// of `pixel` px (a staircase, not a curve), the title in `font.title` at `title.size`/`title.weight` in `title.on`, after
// `title.mark` (a pixel heart); the buttons `title.button_w` px squares with a `pixel`-px outline in the title's ink on the
// lightest surface, their marks on whole pixels — `_`, a nested square (two while the card is full), × — and with
// `title.close = heart` the close button a pixel heart in the accent with a white × in it (the brief's own; the game's
// is a square ×). Only buttons that act are drawn (TitleBase). Static (0 frames idle).
TitleBase {
    id: cap
    property bool full: false

    readonly property int p: Math.max(1, Theme.decor("pixel", 2))
    readonly property var fills: Theme.decor(active ? "title.fill" : "title.fill_inactive", [])
    readonly property color from: fills.length > 0 ? fills[0] : Theme.containerHigh
    readonly property color to: fills.length > 1 ? fills[1] : from
    readonly property string inkActive: Theme.decor("title.on", "")
    readonly property string inkInactive: Theme.decor("title.on_inactive", "")
    readonly property color ink: !active && inkInactive !== "" ? inkInactive : inkActive !== "" ? inkActive : Theme.fg
    readonly property int steps: Math.max(0, Math.round(Math.max(0, Theme.decor("title.radius", -1)) / p))
    readonly property int btn: Theme.decor("title.button_w", 0) > 0 ? Theme.decor("title.button_w", 0) : Math.round(height * 0.76)
    readonly property int gap: Theme.decor("title.button_gap", -1) >= 0 ? Theme.decor("title.button_gap", -1) : 4
    readonly property int inset: Theme.decor("title.inset", -1) >= 0 ? Theme.decor("title.inset", -1) : 4
    readonly property bool heart: Theme.decor("title.close", "glyph") === "heart"
    readonly property var names: (canClose ? ["close"] : []).concat(buttons || [])
    readonly property bool startSide: Theme.decor("title.buttons", "end") === "start"
    readonly property real btnRow: names.length > 0 ? inset + names.length * btn + (names.length - 1) * gap + 6 : inset
    // A staircase corner: how far row r (0 = the top) stands in, in pixels.
    function stair(r) {
        var k = cap.steps
        if (r >= k) return 0
        var dy = k - r - 0.5
        return Math.round(k - Math.sqrt(Math.max(0, k * k - dy * dy)))
    }

    // The band: the stepped top rows, then the rest.
    Repeater {
        model: cap.steps
        Rectangle {
            required property int index
            x: cap.stair(index) * cap.p
            y: index * cap.p
            width: cap.width - 2 * x
            height: cap.p
            color: cap.from
            antialiasing: false
        }
    }
    Rectangle {
        y: cap.steps * cap.p
        width: cap.width
        height: cap.height - y
        antialiasing: false
        gradient: Gradient {
            orientation: Theme.decor("title.fill_dir", "horizontal") === "vertical" ? Gradient.Vertical : Gradient.Horizontal
            GradientStop { position: 0; color: cap.from }
            GradientStop { position: 1; color: cap.to }
        }
    }

    Row {
        id: label
        spacing: 3 * cap.p
        x: cap.startSide ? cap.btnRow : 4 * cap.p
        anchors.verticalCenter: parent.verticalCenter
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: cap.icon !== ""
            name: cap.icon
            size: Math.round(cap.height * 0.62)
            color: cap.ink
        }
        Bullet {
            anchors.verticalCenter: parent.verticalCenter
            kind: Theme.decor("title.mark", "none")
            size: 6 * cap.p
            ink: Theme.accent
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, Math.min(implicitWidth, cap.width - cap.btnRow - label.x - 40))
            text: cap.title
            color: cap.ink
            elide: Text.ElideRight
            font.family: Theme.tok("font.title", "") || Theme.fam(cap.title, Theme.families)
            font.pixelSize: Theme.decor("title.size", 0) > 0 ? Theme.decor("title.size", 0) : Theme.fs
            font.weight: Theme.decor("title.weight", 400)
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
        }
    }

    // A pixel mark: cells (x, y) of a 5 × 5 grid, each `cap.p` square.
    component Cells: Item {
        id: cl
        property var cells: []
        property color tone: cap.ink
        property int px: cap.p
        width: 5 * px
        height: 5 * px
        Repeater {
            model: cl.cells
            Rectangle {
                required property var modelData
                x: modelData[0] * cl.px
                y: modelData[1] * cl.px
                width: cl.px
                height: cl.px
                color: cl.tone
                antialiasing: false
            }
        }
    }
    readonly property var crossCells: [[0, 0], [4, 0], [1, 1], [3, 1], [2, 2], [1, 3], [3, 3], [0, 4], [4, 4]]
    readonly property var minCells: [[0, 4], [1, 4], [2, 4], [3, 4], [4, 4]]
    readonly property var boxCells: [[0, 0], [1, 0], [2, 0], [3, 0], [4, 0], [0, 1], [1, 1], [2, 1], [3, 1], [4, 1],
        [0, 2], [4, 2], [0, 3], [4, 3], [0, 4], [1, 4], [2, 4], [3, 4], [4, 4]]
    readonly property var restoreCells: [[1, 0], [2, 0], [3, 0], [4, 0], [4, 1], [4, 2], [0, 2], [1, 2], [2, 2], [3, 2],
        [0, 3], [3, 3], [0, 4], [1, 4], [2, 4], [3, 4]]

    Row {
        x: cap.startSide ? cap.inset : cap.width - cap.inset - width
        anchors.verticalCenter: parent.verticalCenter
        layoutDirection: cap.startSide ? Qt.LeftToRight : Qt.RightToLeft
        spacing: cap.gap
        Repeater {
            model: cap.names
            Item {
                id: b
                required property string modelData
                readonly property bool isClose: modelData === "close"
                width: cap.btn
                height: cap.btn
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("decor.title." + modelData)
                // A square key: the outline, the face, sunk one pixel while pressed.
                Rectangle {
                    visible: !(b.isClose && cap.heart)
                    anchors.fill: parent
                    color: hit.pressed ? Theme.containerHigh : Theme.color("color.surface_container_lowest", "#ffffff")
                    border.width: cap.p
                    border.color: cap.ink
                    antialiasing: false
                }
                Cells {
                    visible: !(b.isClose && cap.heart)
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: hit.pressed ? cap.p : 0
                    anchors.verticalCenterOffset: hit.pressed ? cap.p : 0
                    cells: b.isClose ? cap.crossCells : b.modelData === "maximize" ? (cap.full ? cap.restoreCells : cap.boxCells) : cap.minCells
                }
                // The heart close: a pixel heart filling the key, a × in the accent's ink in its lobes.
                Bullet {
                    visible: b.isClose && cap.heart
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: hit.pressed ? cap.p : 0
                    kind: "heart"
                    size: Math.floor(cap.btn / 6) * 6
                    ink: hit.pressed ? Qt.darker(Theme.accent, 1.2) : Theme.accent
                }
                Cells {
                    visible: b.isClose && cap.heart
                    px: Math.max(1, Math.round(cap.p / 2))
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: (hit.pressed ? cap.p : 0) - Math.round(cap.btn * 0.08)
                    cells: cap.crossCells
                    tone: Theme.fgOnAccent
                }
                MouseArea {
                    id: hit
                    anchors.fill: parent
                    onClicked: b.isClose ? cap.close() : cap.button(b.modelData)
                }
            }
        }
    }
}
