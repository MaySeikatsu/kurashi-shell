import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"

// The traveller of a layout move (core/Travel.qml; docs/ux/transitions.md): one click-through overlay per output, made
// for the move and gone with it, that draws the bar's body on its way from the old edge to the new one. The body is
// the bar's fill, not its content (a still of live content would freeze the clock; the content fades in as it lands).
//   follow  the body slides along the screen's sides, the shorter way round, as one piece
//   part    it parts in the middle and each half runs down its own side (opposite edges; else as follow)
//   drip    it sags in the middle, drops and settles (top to bottom or back; else as follow)
//   fade    nothing travels: the new bar fades in
// Geometry: the screen's rim as one line, clockwise from the top-left corner — the top edge, the right side between the
// horizontal bars, the bottom edge (right to left), the left side (upward). A bar is a stretch of that line; a move
// slides the stretch's two ends.
Scope {
    id: tv
    required property var modelData
    readonly property string outName: modelData ? modelData.name : ""
    readonly property var move: Travel.moves[outName] || null

    LazyLoader {
        active: tv.move !== null
        PanelWindow {
            id: win
            screen: tv.modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "kurashi-travel"
            color: "transparent"
            mask: Region {}

            readonly property var m: tv.move
            readonly property int serialNo: m ? m.n : -1
            readonly property real th: m ? m.size : 32
            readonly property real sw: width
            readonly property real sh: height
            readonly property real side: Math.max(0, sh - 2 * th)
            readonly property real rim: 2 * sw + 2 * side
            readonly property string how: {
                var s = Travel.style, opp = m && ((m.from === "top" && m.to === "bottom") || (m.from === "bottom" && m.to === "top")
                    || (m.from === "left" && m.to === "right") || (m.from === "right" && m.to === "left"))
                var vert = m && ((m.from === "top" && m.to === "bottom") || (m.from === "bottom" && m.to === "top"))
                if (s === "part" && !opp) return "follow"
                if (s === "drip" && !vert) return "follow"
                return s
            }
            function stretch(edge) {
                return edge === "top" ? [0, sw] : edge === "right" ? [sw, sw + side]
                    : edge === "bottom" ? [sw + side, 2 * sw + side] : [2 * sw + side, rim]
            }
            // The rects of the rim's stretch u0 … u1 (any length, either sign of position).
            function rects(u0, u1, out) {
                if (u1 - u0 < 0.5) return
                var k = Math.floor(u0 / rim) * rim
                u0 -= k; u1 -= k
                var segs = [[0, sw], [sw, sw + side], [sw + side, 2 * sw + side], [2 * sw + side, rim]]
                for (var lap = 0; lap < 2; lap++) {
                    for (var i = 0; i < 4; i++) {
                        var a = Math.max(u0, segs[i][0] + lap * rim), b = Math.min(u1, segs[i][1] + lap * rim)
                        if (b - a < 0.5) continue
                        a -= segs[i][0] + lap * rim; b -= segs[i][0] + lap * rim
                        if (i === 0) out.push({ x: a, y: 0, w: b - a, h: th })
                        else if (i === 1) out.push({ x: sw - th, y: th + a, w: th, h: b - a })
                        else if (i === 2) out.push({ x: sw - b, y: sh - th, w: b - a, h: th })
                        else out.push({ x: 0, y: sh - th - b, w: th, h: b - a })
                    }
                }
            }
            property real t: 0
            readonly property var pieces: {
                var out = [], e = t
                if (!m || how === "fade" || how === "off") return out
                var A = stretch(m.from), B = stretch(m.to)
                if (how === "drip") {
                    // Slices of the body: the middle ones leave first and fall furthest ahead; all land together.
                    var n = 48, y0 = m.from === "top" ? 0 : sh - th, y1 = m.to === "top" ? 0 : sh - th
                    for (var i = 0; i < n; i++) {
                        var c = Math.pow(Math.cos(Math.PI * ((i + 0.5) / n - 0.5)), 2)   // 0 at the ends, 1 in the middle, a round belly
                        var lead = 0.34 * (1 - c)                               // the ends start later
                        var q = Math.max(0, Math.min(1, (e - lead) / (1 - lead)))
                        q = q * q                                               // falling
                        var sag = Math.sin(Math.PI * Math.min(1, e * 2.2)) * c * th * 0.9 * (1 - q)
                        out.push({ x: sw * i / n, y: y0 + (y1 - y0) * q + (y1 > y0 ? sag : -sag), w: sw / n + 0.6, h: th })
                    }
                    return out
                }
                e = e < 0.5 ? 4 * e * e * e : 1 - Math.pow(-2 * e + 2, 3) / 2
                if (how === "part") {
                    var am = (A[0] + A[1]) / 2, b0 = B[0] < A[1] ? B[0] + rim : B[0], b1 = b0 + (B[1] - B[0]), bm = (b0 + b1) / 2
                    rects(am + (b0 - am) * e, A[1] + (bm - A[1]) * e, out)                 // the half that runs clockwise
                    rects(A[0] + (bm - rim - A[0]) * e, am + (b1 - rim - am) * e, out)     // and the one that runs the other way
                    return out
                }
                var d = B[0] - A[0]
                if (d > rim / 2) d -= rim
                else if (d < -rim / 2) d += rim
                // (the new stretch, moved a whole round where the shorter way crosses the rim's start)
                var lap = d - (B[0] - A[0])
                var tail = A[0] + d * e, head = A[1] + (B[1] + lap - A[1]) * e
                rects(tail, head, out)
                return out
            }
            Repeater {
                model: win.pieces
                Rectangle {
                    required property var modelData
                    x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
                    color: Theme.surfaceAlpha
                    opacity: land.fade
                }
            }
            SequentialAnimation {
                id: land
                property real fade: 1
                running: true
                NumberAnimation { target: win; property: "t"; from: 0; to: 1; duration: win.how === "fade" ? 1 : (win.how === "drip" ? 620 : 520) }
                // The bar comes up under the traveller, then the traveller lets go.
                ScriptAction { script: Travel.done(tv.outName, win.serialNo) }
            }
        }
    }
}
