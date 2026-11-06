import QtQuick
import qs.core

// One letter in the overview (K94): drawn, the drawing; not yet, its shadow. A click goes to it. Paints once per change (Ma).
Rectangle {
    id: cell
    property string letter: ""
    property var strokes: null
    property real pen: 56
    property bool current: false
    property var lines: ({ ascent: 1000, descent: -300 })
    signal chosen()
    readonly property real unit: height / (lines.ascent - lines.descent)
    readonly property real baseY: lines.ascent * unit
    radius: Theme.rSm
    color: current ? Theme.selected : "transparent"
    border.width: current ? 2 : 1
    border.color: current ? Theme.accent : Qt.alpha(Theme.outline, 0.35)
    Accessible.role: Accessible.Button
    Accessible.name: letter
    Text {
        visible: !cell.strokes
        anchors.centerIn: parent
        text: cell.letter
        color: Theme.dim
        opacity: 0.35
        font.pixelSize: Math.round(cell.height * 0.5)
        font.family: Theme.fam(text, Theme.families)
    }
    Canvas {
        id: ink
        anchors.fill: parent
        visible: !!cell.strokes
        onPaint: {
            var c = getContext("2d")
            c.reset()
            if (!cell.strokes) return
            c.strokeStyle = Theme.fg
            c.lineWidth = Math.max(1, cell.pen * cell.unit)
            c.lineCap = "round"
            c.lineJoin = "round"
            // (x: centred on the drawing's own middle, the cell is narrower than the box)
            var lo = 1e9, hi = -1e9
            cell.strokes.forEach(function (s) { s.forEach(function (p) { lo = Math.min(lo, p[0]); hi = Math.max(hi, p[0]) }) })
            var dx = width / 2 - (lo + hi) / 2 * cell.unit
            cell.strokes.forEach(function (s) {
                c.beginPath()
                s.forEach(function (p, i) {
                    var x = dx + p[0] * cell.unit, y = cell.baseY - p[1] * cell.unit
                    if (i === 0) c.moveTo(x, y); else c.lineTo(x, y)
                })
                if (s.length === 1) c.lineTo(dx + s[0][0] * cell.unit + 0.1, cell.baseY - s[0][1] * cell.unit)
                c.stroke()
            })
        }
        Connections { target: cell; function onStrokesChanged() { ink.requestPaint() } }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: cell.chosen() }
}
