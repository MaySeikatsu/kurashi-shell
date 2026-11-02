import QtQuick
import "../../core"

// A form as a tiny pictogram of its motion (brief §8 "a tiny glyph per form"): ink lines only — a crease for fold, a scroll
// for roll, a funnel for genie, rings for iris, stairs for stepped … —, so it never reads as a colour swatch. A form
// without its own picture gets a neutral one (a card and a motion arc). Static, drawn once per form (Ma). Decorative: the
// dropdown beside it carries the name.
Canvas {
    id: gl
    property string form: ""
    width: 22
    height: 22
    renderStrategy: Canvas.Cooperative
    Accessible.ignored: true
    onFormChanged: requestPaint()
    property color ink: Theme.fg
    onInkChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        // A unit box (0…1) inside a 2 px margin.
        var o = 2, s = Math.min(width, height) - 2 * o
        function X(u) { return o + u * s }
        function Y(v) { return o + v * s }
        function line(pts) {
            ctx.beginPath(); ctx.moveTo(X(pts[0]), Y(pts[1]))
            for (var i = 2; i < pts.length; i += 2) ctx.lineTo(X(pts[i]), Y(pts[i + 1]))
            ctx.stroke()
        }
        function rect(u, v, w, h) { ctx.strokeRect(X(u), Y(v), w * s, h * s) }
        function ring(u, v, r) { ctx.beginPath(); ctx.arc(X(u), Y(v), r * s, 0, 2 * Math.PI); ctx.stroke() }
        // An arrow from (u0, v0) to (u1, v1), its head 0.18 long.
        function arrow(u0, v0, u1, v1) {
            line([u0, v0, u1, v1])
            var a = Math.atan2(v1 - v0, u1 - u0), h = 0.18
            line([u1 - h * Math.cos(a - 0.5), v1 - h * Math.sin(a - 0.5), u1, v1,
                  u1 - h * Math.cos(a + 0.5), v1 - h * Math.sin(a + 0.5)])
        }
        function faint(f) { ctx.save(); ctx.globalAlpha = 0.4; ctx.setLineDash([2, 2]); f(); ctx.restore() }
        ctx.strokeStyle = Qt.rgba(ink.r, ink.g, ink.b, 0.85)
        ctx.fillStyle = Qt.rgba(ink.r, ink.g, ink.b, 0.85)
        ctx.lineWidth = 1.4
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        // (expand is grow from the middle; matched by a regex, not a quoted name: nix/icon-names.py counts quoted words
        // that are icons)
        var f = /^(expand)$/.test(form) ? "from_middle" : form
        switch (f) {
        case "none": rect(0.1, 0.2, 0.8, 0.6); break                                  // there at once
        case "grow": faint(function () { rect(0.05, 0.05, 0.9, 0.9) }); rect(0.05, 0.6, 0.35, 0.35); arrow(0.45, 0.55, 0.85, 0.15); break
        case "from_middle": faint(function () { rect(0.05, 0.05, 0.9, 0.9) }); rect(0.35, 0.35, 0.3, 0.3)
            arrow(0.3, 0.3, 0.08, 0.08); arrow(0.7, 0.7, 0.92, 0.92); break
        case "slide": faint(function () { rect(0.05, 0.15, 0.55, 0.7) }); rect(0.4, 0.15, 0.55, 0.7); arrow(0.05, 0.5, 0.32, 0.5); break
        case "zoom": faint(function () { rect(0.05, 0.05, 0.9, 0.9) }); rect(0.28, 0.28, 0.44, 0.44); break
        case "outline": rect(0.05, 0.05, 0.9, 0.9); faint(function () { rect(0.22, 0.22, 0.56, 0.56) }); rect(0.4, 0.4, 0.2, 0.2); break
        case "fade": faint(function () { rect(0.1, 0.1, 0.8, 0.8) }); break
        case "dissolve":
            for (var i = 0; i < 4; i++) for (var j = 0; j < 4; j++) if ((i + j) % 2 === 0)
                ctx.fillRect(X(0.1 + i * 0.22), Y(0.1 + j * 0.22), 0.12 * s, 0.12 * s)
            break
        case "bleed":                                                   // a drop of ink spreading into paper
            ctx.beginPath(); ctx.arc(X(0.5), Y(0.5), 0.17 * s, 0, 2 * Math.PI); ctx.fill()
            ctx.save(); ctx.globalAlpha = 0.55; ring(0.5, 0.5, 0.3); ctx.globalAlpha = 0.25; ring(0.5, 0.5, 0.44); ctx.restore(); break
        case "drop": ctx.beginPath(); ctx.moveTo(X(0.5), Y(0.05))
            ctx.bezierCurveTo(X(0.5), Y(0.3), X(0.85), Y(0.5), X(0.85), Y(0.68))
            ctx.arc(X(0.5), Y(0.68), 0.35 * s, 0, Math.PI)
            ctx.bezierCurveTo(X(0.15), Y(0.5), X(0.5), Y(0.3), X(0.5), Y(0.05)); ctx.stroke(); break
        case "liquid": line([0.1, 0.1, 0.9, 0.1, 0.9, 0.6])
            ctx.beginPath(); ctx.moveTo(X(0.9), Y(0.6))
            ctx.bezierCurveTo(X(0.75), Y(0.95), X(0.6), Y(0.55), X(0.45), Y(0.8))
            ctx.bezierCurveTo(X(0.3), Y(1.0), X(0.2), Y(0.6), X(0.1), Y(0.7)); ctx.stroke(); line([0.1, 0.7, 0.1, 0.1]); break
        case "flip": line([0.15, 0.2, 0.6, 0.05, 0.6, 0.95, 0.15, 0.8, 0.15, 0.2])          // a card turning on its edge
            ctx.beginPath(); ctx.arc(X(0.6), Y(0.5), 0.3 * s, -0.9, 0.9); ctx.stroke(); break
        case "book": line([0.5, 0.15, 0.05, 0.05, 0.05, 0.8, 0.5, 0.9, 0.95, 0.8, 0.95, 0.05, 0.5, 0.15, 0.5, 0.9]); break
        case "stepped": line([0.05, 0.95, 0.05, 0.7, 0.35, 0.7, 0.35, 0.4, 0.65, 0.4, 0.65, 0.1, 0.95, 0.1]); break
        case "pixelate":
            for (var p = 0; p < 3; p++) for (var q = 0; q < 3; q++) if (p + q <= 2) rect(0.05 + p * 0.32, 0.05 + q * 0.32, 0.26, 0.26)
            break
        case "rubber": line([0.05, 0.5, 0.18, 0.2, 0.32, 0.8, 0.46, 0.2, 0.6, 0.8, 0.74, 0.25, 0.86, 0.65, 0.95, 0.5]); break   // a spring
        case "iris": ring(0.5, 0.5, 0.45); ring(0.5, 0.5, 0.18)
            for (var k = 0; k < 6; k++) { var an = k * Math.PI / 3
                line([0.5 + 0.18 * Math.cos(an), 0.5 + 0.18 * Math.sin(an), 0.5 + 0.45 * Math.cos(an + 0.6), 0.5 + 0.45 * Math.sin(an + 0.6)]) }
            break
        case "stamp": rect(0.1, 0.55, 0.8, 0.4); arrow(0.5, 0.0, 0.5, 0.45); break
        case "fold": line([0.05, 0.15, 0.35, 0.05, 0.65, 0.15, 0.95, 0.05, 0.95, 0.85, 0.65, 0.95, 0.35, 0.85, 0.05, 0.95, 0.05, 0.15])   // creases
            line([0.35, 0.05, 0.35, 0.85]); line([0.65, 0.15, 0.65, 0.95]); break
        case "fan": for (var r = 0; r < 4; r++) { var b = -Math.PI / 2 + r * Math.PI / 6
                line([0.1, 0.9, 0.1 + 0.85 * Math.cos(b), 0.9 + 0.85 * Math.sin(b)]) }
            ctx.beginPath(); ctx.arc(X(0.1), Y(0.9), 0.85 * s, -Math.PI / 2, 0); ctx.stroke(); break
        case "noren": line([0.05, 0.1, 0.95, 0.1])                                               // a split curtain
            rect(0.1, 0.1, 0.22, 0.75); rect(0.39, 0.1, 0.22, 0.85); rect(0.68, 0.1, 0.22, 0.7); break
        case "roll": rect(0.15, 0.05, 0.7, 0.55); ring(0.5, 0.78, 0.17); line([0.15, 0.6, 0.33, 0.78]); line([0.85, 0.6, 0.67, 0.78]); break   // a scroll
        case "crumple": line([0.1, 0.15, 0.4, 0.05, 0.55, 0.25, 0.9, 0.1, 0.8, 0.5, 0.95, 0.85, 0.55, 0.75, 0.3, 0.95, 0.2, 0.6, 0.05, 0.45, 0.1, 0.15]); break
        case "genie": line([0.05, 0.05, 0.95, 0.05]); ctx.beginPath(); ctx.moveTo(X(0.05), Y(0.05))   // a funnel
            ctx.bezierCurveTo(X(0.1), Y(0.5), X(0.4), Y(0.6), X(0.45), Y(0.95)); ctx.moveTo(X(0.95), Y(0.05))
            ctx.bezierCurveTo(X(0.9), Y(0.5), X(0.6), Y(0.6), X(0.55), Y(0.95)); ctx.stroke(); break
        case "crt": faint(function () { rect(0.05, 0.1, 0.9, 0.8) }); line([0.1, 0.5, 0.9, 0.5]); arrow(0.5, 0.12, 0.5, 0.4); arrow(0.5, 0.88, 0.5, 0.6); break
        case "glitch": line([0.05, 0.2, 0.7, 0.2]); line([0.3, 0.42, 0.95, 0.42]); line([0.1, 0.64, 0.6, 0.64]); line([0.4, 0.86, 0.9, 0.86]); break
        case "": break
        default:                                                                                    // any other form
            rect(0.3, 0.3, 0.6, 0.6)
            ctx.beginPath(); ctx.arc(X(0.3), Y(0.9), 0.6 * s, -Math.PI / 2, -Math.PI * 0.08); ctx.stroke()
        }
    }
}
