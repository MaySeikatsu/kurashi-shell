import QtQuick
import qs.core

// The box a letter is drawn in (K94, docs/ux/handwriting.md): the letter due as a shadow, the same lines a page has (where capitals reach,
// where small letters reach, the line it stands on, how far tails hang), so a letter lands at the right height. The pointer or a pen draws;
// strokes come out in font units, y up, baseline 0. It paints only while something changes (Ma).
Item {
    id: box
    property string letter: ""
    property real pen: 56
    property var lines: ({ cap: 720, x: 480, ascent: 1000, descent: -300 })
    // The strokes on the box now, each a list of [x, y] in font units.
    property var strokes: []
    readonly property real unit: height / (lines.ascent - lines.descent)
    readonly property real baseY: lines.ascent * unit
    function yOf(v) { return baseY - v * unit }
    function show(list) { strokes = list; ink.requestPaint() }
    function clear() { show([]) }
    function undo() { strokes = strokes.slice(0, -1); ink.requestPaint() }

    Rectangle { anchors.fill: parent; radius: Theme.rSm; color: Theme.containerHigh; border.width: 1; border.color: Theme.outline }

    // The shadow: the shell's own font, sized so its small letters reach the line for them, standing on the baseline.
    FontMetrics { id: fm; font.family: Theme.fam(box.letter, Theme.families); font.pixelSize: 100 }
    readonly property real shadowPx: fm.xHeight > 0 ? 100 * (lines.x * unit) / fm.xHeight : height * 0.5
    FontMetrics { id: fmAt; font.family: fm.font.family; font.pixelSize: Math.max(1, Math.round(box.shadowPx)) }
    Text {
        id: shadow
        objectName: "handwriting-shadow"
        x: (box.width - implicitWidth) / 2
        y: box.baseY - fmAt.ascent
        text: box.letter
        color: Theme.fg
        opacity: 0.16
        font: fmAt.font
    }

    component Line: Item {
        property real at: 0
        property string name: ""
        property bool strong: false
        x: 0
        width: box.width
        y: box.yOf(at)
        height: 1
        Rectangle { width: parent.width; height: parent.strong ? 2 : 1; color: Theme.accent; opacity: parent.strong ? 0.55 : 0.28 }
        Text {
            x: 6
            y: -implicitHeight
            text: parent.name
            color: Theme.dim
            opacity: 0.8
            font.pixelSize: Theme.fsCaption - 1
            font.family: Theme.fam(text, Theme.families)
        }
    }
    Line { at: box.lines.cap; name: I18n.tr("mod-handwriting.line.cap") }
    Line { at: box.lines.x; name: I18n.tr("mod-handwriting.line.x") }
    Line { at: 0; name: I18n.tr("mod-handwriting.line.base"); strong: true }
    Line { at: box.lines.descent + 60; name: I18n.tr("mod-handwriting.line.tail") }

    Canvas {
        id: ink
        anchors.fill: parent
        onPaint: {
            var c = getContext("2d")
            c.reset()
            c.strokeStyle = Theme.fg
            c.fillStyle = Theme.fg
            c.lineWidth = box.pen * box.unit
            c.lineCap = "round"
            c.lineJoin = "round"
            box.strokes.forEach(function (s) {
                c.beginPath()
                var px = function (p) { return [p[0] * box.unit, box.baseY - p[1] * box.unit] }
                var a = px(s[0])
                c.moveTo(a[0], a[1])
                if (s.length === 1) c.lineTo(a[0] + 0.1, a[1])
                // (as the font will have it: through the midpoints)
                for (var i = 1; i < s.length - 1; i++) {
                    var q = px(s[i]), r = px(s[i + 1])
                    c.quadraticCurveTo(q[0], q[1], (q[0] + r[0]) / 2, (q[1] + r[1]) / 2)
                }
                if (s.length > 1) { var z = px(s[s.length - 1]); c.lineTo(z[0], z[1]) }
                c.stroke()
            })
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        preventStealing: true
        function at(m) { return [Math.round(m.x / box.unit), Math.round((box.baseY - m.y) / box.unit)] }
        onPressed: m => { box.strokes = box.strokes.concat([[at(m)]]); ink.requestPaint() }
        onPositionChanged: m => {
            if (!pressed || box.strokes.length === 0) return
            var s = box.strokes[box.strokes.length - 1], p = at(m), last = s[s.length - 1]
            // (under two font units is under a pixel)
            if (Math.abs(p[0] - last[0]) + Math.abs(p[1] - last[1]) < 4) return
            s.push(p)
            ink.requestPaint()
        }
    }
}
