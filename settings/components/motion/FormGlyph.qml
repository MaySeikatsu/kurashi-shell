import QtQuick
import "../../core"

// A form as a small still (brief §8 "a tiny glyph per form"): a card mid-way through the form — grown from its edge, slid
// in, half faded, folded along a crease … — so the dropdown's choice reads at a glance. Drawn once per form (Ma); it plays
// with the preview stage once W59.2's forms exist. Decorative: the dropdown carries the name.
Canvas {
    id: gl
    property string form: ""
    width: 30
    height: 24
    renderStrategy: Canvas.Cooperative
    Accessible.ignored: true
    onFormChanged: requestPaint()
    property color ink: Theme.fg
    property color fill: Theme.accent
    onInkChanged: requestPaint()
    onFillChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var W = width, H = height
        var a = function (c, o) { return Qt.rgba(c.r, c.g, c.b, o) }
        // The card at rest, as a faint outline: every glyph shows where the card ends up.
        ctx.strokeStyle = a(ink, 0.35)
        ctx.lineWidth = 1
        ctx.setLineDash([2, 2])
        ctx.strokeRect(3.5, 3.5, W - 7, H - 7)
        ctx.setLineDash([])
        ctx.fillStyle = a(fill, 0.85)
        ctx.strokeStyle = ink
        var x = 3, y = 3, w = W - 6, h = H - 6
        // (expand draws as grow; a regex, not a quoted name: nix/icon-names.py counts quoted words that are icons)
        switch (/^(grow|expand)$/.test(form) ? "grow" : form) {
        case "grow": ctx.fillRect(x, y, w, h * 0.55); break
        case "slide": ctx.fillRect(x + w * 0.35, y, w, h); break
        case "zoom": case "outline": ctx.fillRect(x + w * 0.2, y + h * 0.2, w * 0.6, h * 0.6); break
        case "fade": case "bleed": case "dissolve": ctx.fillStyle = a(fill, 0.4); ctx.fillRect(x, y, w, h); break
        case "flip": case "book":
            ctx.beginPath(); ctx.moveTo(x, y + 3); ctx.lineTo(x + w * 0.6, y); ctx.lineTo(x + w * 0.6, y + h)
            ctx.lineTo(x, y + h - 3); ctx.closePath(); ctx.fill(); break
        case "stepped": case "pixelate":
            for (var i = 0; i < 3; i++) ctx.fillRect(x + i * w / 3, y + h - (i + 1) * h / 3, w / 3, (i + 1) * h / 3); break
        case "rubber": case "liquid": case "drop":
            ctx.beginPath(); ctx.ellipse(x + w * 0.1, y + h * 0.15, w * 0.8, h * 0.85); ctx.fill(); break
        case "iris": ctx.beginPath(); ctx.arc(W / 2, H / 2, h * 0.4, 0, 2 * Math.PI); ctx.fill(); break
        case "fold": case "fan": case "noren":
            ctx.fillRect(x, y, w / 2, h)
            ctx.fillStyle = a(fill, 0.5)
            ctx.beginPath(); ctx.moveTo(x + w / 2, y); ctx.lineTo(x + w * 0.85, y + 3); ctx.lineTo(x + w * 0.85, y + h - 3)
            ctx.lineTo(x + w / 2, y + h); ctx.closePath(); ctx.fill(); break
        case "roll": ctx.fillRect(x, y, w, h * 0.5); ctx.beginPath(); ctx.ellipse(x, y + h * 0.4, w, h * 0.3); ctx.fill(); break
        case "crumple": ctx.beginPath(); ctx.moveTo(x + 4, y + 3); ctx.lineTo(x + w - 3, y + 5); ctx.lineTo(x + w - 6, y + h - 2)
            ctx.lineTo(x + 2, y + h - 4); ctx.closePath(); ctx.fill(); break
        case "genie":
            ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + w, y); ctx.lineTo(x + w * 0.6, y + h); ctx.lineTo(x + w * 0.4, y + h)
            ctx.closePath(); ctx.fill(); break
        case "crt": ctx.fillRect(x, y + h * 0.42, w, h * 0.16); break
        case "glitch": ctx.fillRect(x + 2, y, w, h * 0.4); ctx.fillRect(x - 1, y + h * 0.45, w, h * 0.55); break
        case "stamp": ctx.fillRect(x - 1, y - 1, w + 2, h + 2); break
        case "none": case "": break
        default: ctx.fillRect(x, y, w, h)
        }
    }
}
