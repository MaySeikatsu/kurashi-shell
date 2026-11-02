import QtQuick
import "../../core"
import ".."
import "curvemath.js" as CM

// The curve editor's graph (brief docs/ux/motion-engine.md §8, cubic-bezier.com's model): time runs left to right, progress
// bottom to top over y −0.5 … 1.5, so an overshoot shows in the shaded band above 1 (and an anticipation below 0); the
// dashed diagonal is linear for reference. A single cubic gets two handles: drag them, or Tab to one and nudge it with the
// arrows (0.01, Shift 0.1); Return commits, Escape reverts. Every edit is a draft (`moved`) until `commit`. A ball races a
// linear ghost when `play()` is called (on demand only, never by itself: Ma), on a track at the right edge.
Item {
    id: g
    // {kind: cubic|spring|spring_q|steps|linear, …} (curvemath.js), or null (no motion).
    property var curve: null
    // The curve's duration (the ball's run and the spring's span), ms.
    property real ms: 500
    // A curve to compare with (the profile's own, K83 profile_curve), drawn faint and dashed under the curve and named
    // in its corner; null for none. Each is drawn over its own run.
    property var reference: null
    property real referenceMs: 0
    readonly property bool referenced: !!g.reference && g.reference.kind !== "spring_q"
        && CM.canonicalCurve(g.reference) !== (g.curve ? CM.canonicalCurve(g.curve) : "")
    // Handles are offered for a single cubic while this is on.
    property bool editable: false
    // The row's key (objectNames) and label (accessible names).
    property string key: ""
    property string label: ""
    // Draft edits: the four control numbers of the cubic after a handle moved.
    signal moved(var points)
    signal commit()
    signal revert()

    function isCubic1(c) { return !!c && c.kind === "cubic" && Array.isArray(c.points) && c.points.length === 6 }
    readonly property bool cubic1: isCubic1(curve)
    readonly property bool handles: g.editable && g.cubic1
    // The handles' y range (read from the curve itself: cubic1 may not have caught up with a new curve yet).
    readonly property var handleY: isCubic1(curve) ? [Math.min(curve.points[1], curve.points[3]), Math.max(curve.points[1], curve.points[3])] : [0, 1]
    readonly property real span: curve ? CM.spanOf(curve, ms) : 0
    readonly property var ext: curve && curve.kind !== "spring_q" ? CM.extent(curve) : ({ max: 1, min: 0 })
    // The y range shown: −0.5 … 1.5, wider when a handle or the curve needs it; held still while a handle is dragged so the
    // handle stays under the pointer.
    property bool latched: false
    property real latchedMin: -0.5
    property real latchedMax: 1.5
    readonly property real autoMin: Math.min(-0.5, ext.min - 0.1, handleY[0] - 0.1)
    readonly property real autoMax: Math.max(1.5, ext.max + 0.1, handleY[1] + 0.1)
    readonly property real yMin: latched ? latchedMin : autoMin
    readonly property real yMax: latched ? latchedMax : autoMax

    // The plot area inside the item: room for the band labels left and the ball's track right.
    readonly property real padL: 8
    readonly property real padR: 28
    readonly property real padT: 8
    readonly property real padB: 8
    readonly property real plotW: width - padL - padR
    readonly property real plotH: height - padT - padB
    function px(x) { return padL + x * plotW }
    function py(y) { return padT + (yMax - y) / (yMax - yMin) * plotH }
    function fromPx(mx, my) {
        return { x: (mx - padL) / plotW, y: yMax - (my - padT) / plotH * (yMax - yMin) }
    }
    function round2(v) { return Math.round(v * 100) / 100 }

    implicitWidth: 240 + padL + padR
    implicitHeight: 240 + padT + padB

    // The ball: t ∈ [0, 1] while a play runs, −1 otherwise.
    property real t: -1
    function play() {
        if (!g.curve || g.curve.kind === "spring_q") return
        run.duration = Math.max(300, Math.min(2000, g.span > 0 ? g.span : 500))
        run.restart()
    }
    NumberAnimation {
        id: run
        target: g
        property: "t"
        from: 0
        to: 1
        onStopped: g.t = -1
    }
    // Stops with the window (Ma): a hidden page draws nothing.
    onVisibleChanged: if (!visible) run.stop()
    readonly property real ballY: g.t < 0 || !g.curve ? 0 : CM.sample(g.curve, g.t, g.span)

    onCurveChanged: canvas.requestPaint()
    onReferenceChanged: canvas.requestPaint()
    onYMinChanged: canvas.requestPaint()
    onYMaxChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    Connections {
        target: Theme
        function onFgChanged() { canvas.requestPaint() }
        function onAccentChanged() { canvas.requestPaint() }
    }

    Rectangle {
        x: g.padL
        y: g.padT
        width: g.plotW
        height: g.plotH
        radius: Theme.rSm
        color: Theme.containerHigh
        border.width: 1
        border.color: Theme.outline
    }
    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var x0 = g.px(0), x1 = g.px(1)
            // The overshoot band: above 1 and below 0.
            ctx.fillStyle = rgba(Theme.accent, 0.06)
            ctx.fillRect(x0, g.py(g.yMax), x1 - x0, g.py(1) - g.py(g.yMax))
            ctx.fillRect(x0, g.py(0), x1 - x0, g.py(g.yMin) - g.py(0))
            // 0 and 1, dashed; the quarters of time, faint.
            ctx.lineWidth = 1
            ctx.strokeStyle = rgba(Theme.fg, 0.35)
            ctx.setLineDash([4, 4])
            ctx.beginPath()
            ctx.moveTo(x0, g.py(0)); ctx.lineTo(x1, g.py(0))
            ctx.moveTo(x0, g.py(1)); ctx.lineTo(x1, g.py(1))
            ctx.stroke()
            ctx.strokeStyle = rgba(Theme.fg, 0.12)
            ctx.beginPath()
            for (var q = 1; q < 4; q++) { ctx.moveTo(g.px(q / 4), g.py(g.yMin)); ctx.lineTo(g.px(q / 4), g.py(g.yMax)) }
            ctx.stroke()
            // Linear, for reference.
            ctx.strokeStyle = rgba(Theme.fg, 0.30)
            ctx.beginPath()
            ctx.moveTo(g.px(0), g.py(0)); ctx.lineTo(g.px(1), g.py(1))
            ctx.stroke()
            if (g.referenced) {
                ctx.strokeStyle = rgba(Theme.accent, 0.55)
                ctx.lineWidth = 1.5
                ctx.setLineDash([6, 4])
                trace(ctx, g.reference, CM.spanOf(g.reference, g.referenceMs > 0 ? g.referenceMs : g.ms))
                ctx.stroke()
            }
            ctx.setLineDash([])
            var c = g.curve
            if (!c || c.kind === "spring_q") return
            // The handles' arms, under the curve.
            if (g.handles) {
                ctx.strokeStyle = rgba(Theme.accent, 0.8)
                ctx.lineWidth = 1.5
                ctx.beginPath()
                ctx.moveTo(g.px(0), g.py(0)); ctx.lineTo(g.px(c.points[0]), g.py(c.points[1]))
                ctx.moveTo(g.px(1), g.py(1)); ctx.lineTo(g.px(c.points[2]), g.py(c.points[3]))
                ctx.stroke()
            }
            ctx.strokeStyle = Theme.fg
            ctx.lineWidth = 2.5
            ctx.lineJoin = "round"
            trace(ctx, c, g.span)
            ctx.stroke()
        }
        // One curve's path over the plot.
        function trace(ctx, c, span) {
            ctx.beginPath()
            ctx.moveTo(g.px(0), g.py(0))
            if (c.kind === "cubic") {
                // Exact: the map to pixels is affine, so the segments' control points map as they are.
                for (var i = 0; i < c.points.length; i += 6) {
                    var p = c.points
                    ctx.bezierCurveTo(g.px(p[i]), g.py(p[i + 1]), g.px(p[i + 2]), g.py(p[i + 3]), g.px(p[i + 4]), g.py(p[i + 5]))
                }
            } else if (c.kind === "steps") {
                for (var s = 0; s < c.n; s++) {
                    ctx.lineTo(g.px((s + 1) / c.n), g.py(s / c.n))
                    ctx.lineTo(g.px((s + 1) / c.n), g.py((s + 1) / c.n))
                }
            } else {
                for (var k = 1; k <= 160; k++) ctx.lineTo(g.px(k / 160), g.py(CM.sample(c, k / 160, span)))
            }
        }
    }
    // The reference named in words (dashed, so not colour alone).
    MotionText {
        objectName: "curve-reference:" + g.key
        visible: g.referenced
        x: g.padL + g.plotW - width - 4
        y: g.padT + g.plotH - height - 4
        small: true
        color: Theme.accent
        text: "– – " + I18n.tr("motion.ui.curve.reference")
    }
    // How far the curve overshoots (or pulls back), named on the band: never colour alone.
    MotionText {
        visible: !!g.curve && g.curve.kind !== "spring_q" && g.ext.max > 1.001
        x: g.padL + 4
        y: Math.max(g.padT + 2, g.py(g.ext.max) - height - 2)
        small: true
        color: Theme.dim
        text: I18n.fmt("motion.ui.curve.overshoot", { n: Math.round((g.ext.max - 1) * 100) })
    }
    MotionText {
        visible: !!g.curve && g.curve.kind !== "spring_q" && g.ext.min < -0.001
        x: g.padL + 4
        y: Math.min(g.padT + g.plotH - height - 2, g.py(g.ext.min) + 2)
        small: true
        color: Theme.dim
        text: I18n.fmt("motion.ui.curve.undershoot", { n: Math.round(-g.ext.min * 100) })
    }
    // No curve to draw: motion off, or one of the shell's own springs (calm, lively: K42 units, no text form).
    MotionText {
        visible: !g.curve || g.curve.kind === "spring_q"
        anchors.centerIn: parent
        width: g.plotW - 2 * Theme.pad
        horizontalAlignment: Text.AlignHCenter
        color: Theme.dim
        text: I18n.tr(!g.curve ? "motion.ui.curve.none" : "motion.ui.curve.spring_q")
    }

    // The ball on the curve, its twin on the track at the right edge, and the linear ghost beside it.
    Rectangle {
        visible: g.t >= 0
        width: 10; height: 10; radius: 5
        x: g.px(g.t) - 5
        y: g.py(g.ballY) - 5
        color: Theme.accent
    }
    Rectangle {
        visible: g.t >= 0
        x: g.width - g.padR / 2 - 1
        y: g.py(g.yMax)
        width: 2
        height: g.py(g.yMin) - g.py(g.yMax)
        color: Theme.outline
    }
    Rectangle {
        visible: g.t >= 0
        width: 10; height: 10; radius: 5
        x: g.width - g.padR / 2 - 5
        y: g.py(g.t) - 5
        color: "transparent"
        border.width: 1
        border.color: Theme.dim
    }
    Rectangle {
        visible: g.t >= 0
        width: 12; height: 12; radius: 6
        x: g.width - g.padR / 2 - 6
        y: g.py(g.ballY) - 6
        color: Theme.accent
    }

    // The two handles (control points 1 and 2 of the cubic).
    Repeater {
        model: g.handles ? 2 : 0
        delegate: Item {
            id: h
            required property int index
            readonly property real hx: g.isCubic1(g.curve) ? g.curve.points[index * 2] : 0
            readonly property real hy: g.isCubic1(g.curve) ? g.curve.points[index * 2 + 1] : 0
            objectName: "curve-handle:" + g.key + ":" + (index + 1)
            x: g.px(hx) - width / 2
            y: g.py(hy) - height / 2
            width: 22
            height: 22
            activeFocusOnTab: true
            Accessible.role: Accessible.Slider
            Accessible.name: I18n.fmt("motion.ui.curve.handle", { n: index + 1, x: hx.toFixed(2), y: hy.toFixed(2) })
            Accessible.description: g.label
            function nudge(dx, dy) {
                var p = g.curve.points.slice(0, 4)
                p[index * 2] = g.round2(Math.max(0, Math.min(1, hx + dx)))
                p[index * 2 + 1] = g.round2(Math.max(-1, Math.min(2, hy + dy)))
                g.moved(p)
            }
            Keys.onPressed: event => {
                const d = (event.modifiers & Qt.ShiftModifier) ? 0.1 : 0.01
                switch (event.key) {
                case Qt.Key_Left: h.nudge(-d, 0); break
                case Qt.Key_Right: h.nudge(d, 0); break
                case Qt.Key_Up: h.nudge(0, d); break
                case Qt.Key_Down: h.nudge(0, -d); break
                case Qt.Key_Return: case Qt.Key_Enter: g.commit(); break
                case Qt.Key_Escape: g.revert(); break
                default: return
                }
                event.accepted = true
            }
            Rectangle {
                anchors.centerIn: parent
                width: 14; height: 14; radius: 7
                color: h.activeFocus || drag.pressed ? Theme.accent : Theme.surface
                border.width: 2
                border.color: Theme.accent
            }
            FocusRing {
                anchors.fill: parent
                shown: h.activeFocus
                corner: width / 2
            }
            MouseArea {
                id: drag
                anchors.fill: parent
                anchors.margins: -4
                preventStealing: true
                cursorShape: Qt.SizeAllCursor
                onPressed: { g.latchedMin = g.yMin; g.latchedMax = g.yMax; g.latched = true }
                onPositionChanged: mouse => {
                    if (!pressed) return
                    var at = mapToItem(g, mouse.x, mouse.y)
                    var v = g.fromPx(at.x, at.y)
                    h.nudge(g.round2(Math.max(0, Math.min(1, v.x))) - h.hx, g.round2(Math.max(-1, Math.min(2, v.y))) - h.hy)
                }
                onReleased: { g.latched = false; g.commit() }
                onCanceled: { g.latched = false; g.revert() }
            }
        }
    }
}
