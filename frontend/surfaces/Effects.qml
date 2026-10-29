import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"

// The effects sheet (W53.0b, K80, I312, I317): the pointer decoration — a trail as in osu!, sparkles, or a ring — drawn
// over everything (apps included) on the pointer's output. The daemon names the decoration (`svc.cursor.decoration`:
// `cursor.decoration`, or the style's own; "" = none) and says where the pointer is (`svc.pointer`, K79: cursor sessions
// over the whole screen). Off by default.
// Ma: `svc.pointer` is watched (its sessions run) only while a decoration is chosen; the sheet — a layer surface with an
// empty input region (clicks pass through), exclusion ignored, no keyboard — exists only while the pointer moves and its
// marks fade, and is gone a moment after the pointer rests (I312: made only while an effect runs). Where the compositor
// cannot say where the pointer is (`available` false), nothing is drawn: a client sees the pointer only over its own
// surfaces, and Settings says why. Motion off (reduced motion too): no decoration.
Scope {
    id: fx

    Watch { doc: "svc.cursor" }
    readonly property string kind: Theme.motionKind === "none" ? "" : ((Store.docs["svc.cursor"] || {}).decoration || "")
    Watch { doc: "svc.pointer"; active: fx.kind !== "" }
    readonly property var pointer: kind !== "" ? (Store.docs["svc.pointer"] || {}) : ({})
    readonly property bool available: pointer.available === true

    // The marks: {x, y, t, vx, vy, s} in output px; `t` ms since the epoch.
    property var marks: []
    property string output: ""
    property real lastX: -1
    property real lastY: -1
    // How long a mark lives (ms); the sheet goes away this long after the last move.
    readonly property int life: kind === "sparkles" ? 650 : (kind === "ring" ? 420 : 280)
    property bool running: false

    onPointerChanged: {
        if (!available || !pointer.output) return
        var now = Date.now()
        if (pointer.output !== output) { marks = []; output = pointer.output; lastX = -1 }
        var x = pointer.x, y = pointer.y
        var m = marks.filter(function (k) { return now - k.t < fx.life })
        if (kind === "sparkles") {
            // A few sparks per move, more for a faster one; they drift and fall.
            var d = lastX < 0 ? 0 : Math.hypot(x - lastX, y - lastY)
            var n = Math.min(3, 1 + Math.floor(d / 24))
            for (var i = 0; i < n; i++)
                m.push({ x: x + (Math.random() - 0.5) * 10, y: y + (Math.random() - 0.5) * 10, t: now,
                         vx: (Math.random() - 0.5) * 0.06, vy: 0.02 + Math.random() * 0.05, s: 2 + Math.random() * 3 })
        } else {
            m.push({ x: x, y: y, t: now, vx: 0, vy: 0, s: 0 })
        }
        if (m.length > 64) m = m.slice(m.length - 64)
        marks = m
        lastX = x; lastY = y
        running = true
        rest.restart()
    }
    // Not drawn once the switch goes off or the pointer cannot be followed.
    onKindChanged: if (kind === "") { running = false; marks = [] }
    onAvailableChanged: if (!available) { running = false; marks = [] }
    Timer {
        id: rest
        interval: fx.life + 120
        onTriggered: { fx.running = false; fx.marks = [] }
    }

    LazyLoader {
        active: fx.running && fx.kind !== "" && fx.available
        PanelWindow {
            id: sheet
            screen: {
                for (var i = 0; i < Quickshell.screens.length; i++)
                    if (Quickshell.screens[i].name === fx.output) return Quickshell.screens[i]
                return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
            }
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "kurashi-effects"
            color: "transparent"
            mask: Region {}

            Canvas {
                id: canvas
                anchors.fill: parent
                renderStrategy: Canvas.Cooperative
                // One paint per frame while marks live; none at rest (the window is gone then).
                FrameAnimation {
                    running: fx.running
                    onTriggered: canvas.requestPaint()
                }
                onPaint: {
                    var g = getContext("2d")
                    g.reset()
                    var now = Date.now(), m = fx.marks, life = fx.life
                    if (fx.kind === "trail") {
                        // A ribbon from the oldest mark to the newest, thin and faint at its tail (butt caps: round ones
                        // overlap where the segments meet and bead the translucent ribbon).
                        g.lineCap = "butt"
                        g.lineJoin = "round"
                        for (var i = 1; i < m.length; i++) {
                            var a = 1 - (now - m[i].t) / life
                            if (a <= 0) continue
                            g.strokeStyle = Qt.alpha(Theme.accent, 0.85 * a)
                            g.lineWidth = 2 + 6 * a
                            g.beginPath()
                            g.moveTo(m[i - 1].x, m[i - 1].y)
                            g.lineTo(m[i].x, m[i].y)
                            g.stroke()
                        }
                    } else if (fx.kind === "sparkles") {
                        for (var j = 0; j < m.length; j++) {
                            var age = now - m[j].t, b = 1 - age / life
                            if (b <= 0) continue
                            var sx = m[j].x + m[j].vx * age, sy = m[j].y + m[j].vy * age, r = m[j].s * (0.4 + 0.6 * b)
                            g.fillStyle = Qt.alpha(j % 2 ? Theme.accent : Theme.secondary, b)
                            // A four-pointed star.
                            g.beginPath()
                            g.moveTo(sx, sy - 2 * r)
                            g.quadraticCurveTo(sx, sy, sx + 2 * r, sy)
                            g.quadraticCurveTo(sx, sy, sx, sy + 2 * r)
                            g.quadraticCurveTo(sx, sy, sx - 2 * r, sy)
                            g.quadraticCurveTo(sx, sy, sx, sy - 2 * r)
                            g.fill()
                        }
                    } else if (fx.kind === "ring" && m.length > 0) {
                        // A ring round the pointer that widens and fades once it stops.
                        var last = m[m.length - 1], k = Math.min(1, (now - last.t) / life)
                        g.strokeStyle = Qt.alpha(Theme.accent, 0.9 * (1 - k))
                        g.lineWidth = 2
                        g.beginPath()
                        g.arc(last.x, last.y, 14 + 10 * k, 0, 2 * Math.PI)
                        g.stroke()
                    }
                }
            }
        }
    }
}
