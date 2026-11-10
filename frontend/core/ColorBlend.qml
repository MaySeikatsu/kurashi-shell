import QtQuick
import Quickshell

// K87 (docs/ux/dynamic-media-color.md): the change of colour under Dynamic Media Color. The daemon owns the colours and
// sends the new tokens at once; this only draws the way there, through Theme.liveColors, when `media.tint` changes (a new
// cover, the switch, the track gone). I472 (K117): any other change of colour fades too, quickly (`motion.blend_colors`);
// with that off it stays a cut, as it always was. At rest the overlay is null and
// the timer stopped (rule 5); motion off or `media.blend = direct` cuts. Colours in Oklab, so a fade does not go muddy.
Scope {
    id: cb
    readonly property var tokens: Theme.tokens
    property string tint: ""
    property var rest: null     // the colours in the tokens now
    property var from: null
    property var to: null
    property var shown: null    // the colours on screen while a blend runs
    property double startedAt: 0
    property int runMs: 1200
    property string kind: "fade"
    property real turn: 0       // the wheel's way round, radians

    function isColor(v) { return typeof v === "string" && /^#[0-9a-fA-F]{6,8}$/.test(v) }
    // Every colour token, a list's entries (`decor.bar.fill`) as `key[i]`.
    function flat(t) {
        var out = ({})
        for (var k in t) {
            var v = t[k]
            if (isColor(v)) out[k] = v
            else if (Array.isArray(v) && v.length > 0 && v.every(isColor))
                for (var i = 0; i < v.length; i++) out[k + "[" + i + "]"] = v[i]
        }
        return out
    }
    function assembled(f) {
        var out = ({})
        for (var k in f) {
            var m = /^(.*)\[(\d+)\]$/.exec(k), c = "" + f[k]
            if (!m) { out[k] = c; continue }
            if (!out[m[1]]) out[m[1]] = []
            out[m[1]][Number(m[2])] = c
        }
        return out
    }
    function lin(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4) }
    function gam(c) { c = Math.max(0, Math.min(1, c)); return c <= 0.0031308 ? c * 12.92 : 1.055 * Math.pow(c, 1 / 2.4) - 0.055 }
    function lab(col) {
        var c = Qt.color(col), r = lin(c.r), g = lin(c.g), b = lin(c.b)
        var l = Math.cbrt(0.41222 * r + 0.53633 * g + 0.05145 * b), m = Math.cbrt(0.21190 * r + 0.68070 * g + 0.10740 * b)
        var s = Math.cbrt(0.08830 * r + 0.28172 * g + 0.62998 * b)
        return { L: 0.21045 * l + 0.79362 * m - 0.00407 * s, a: 1.97800 * l - 2.42859 * m + 0.45059 * s,
                 b: 0.02590 * l + 0.78277 * m - 0.80868 * s, A: c.a }
    }
    function rgb(p) {
        var l = Math.pow(p.L + 0.39634 * p.a + 0.21580 * p.b, 3), m = Math.pow(p.L - 0.10556 * p.a - 0.06385 * p.b, 3)
        var s = Math.pow(p.L - 0.08948 * p.a - 1.29149 * p.b, 3)
        return Qt.rgba(gam(4.07674 * l - 3.30771 * m + 0.23097 * s), gam(-1.26844 * l + 2.60976 * m - 0.34132 * s),
                       gam(-0.00420 * l - 0.70342 * m + 1.70761 * s), p.A)
    }
    function wrap(a) { var w = (a + Math.PI) % (2 * Math.PI); if (w < 0) w += 2 * Math.PI; return w - Math.PI }
    function ease(t) { return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2 }

    // The surface's way round the wheel: every colour turns by it, plus its own short rest, so a surface and its containers
    // do not part ways mid-blend.
    function surfaceTurn() {
        var a = lab(from["color.surface"] || "#808080"), b = lab(to["color.surface"] || "#808080")
        var d = wrap(Math.atan2(b.b, b.a) - Math.atan2(a.b, a.a))
        return kind === "wheel_furthest" ? d - (d >= 0 ? 2 : -2) * Math.PI : d
    }
    function step(k, t) {
        var a = from[k], b = to[k]
        if (a === undefined || a === b) return b
        var p = lab(a), q = lab(b), A = p.A + (q.A - p.A) * t, L = p.L + (q.L - p.L) * t
        if (kind === "fade") return rgb({ L: L, a: p.a + (q.a - p.a) * t, b: p.b + (q.b - p.b) * t, A: A })
        var h0 = Math.atan2(p.b, p.a), h1 = Math.atan2(q.b, q.a)
        var h = h0 + (turn + wrap(h1 - h0 - turn)) * t
        // The colour lifted mid-way, so greys turn too.
        var C = Math.hypot(p.a, p.b) * (1 - t) + Math.hypot(q.a, q.b) * t + 0.07 * Math.sin(Math.PI * t)
        return rgb({ L: L, a: C * Math.cos(h), b: C * Math.sin(h), A: A })
    }
    // Whether any colour both have is another one now (a new or a gone key alone is no reason to fade).
    function differ(a, b) {
        for (var k in b) if (a[k] !== undefined && a[k] !== b[k]) return true
        return false
    }
    function paint(t) {
        var out = ({})
        for (var k in to) out[k] = "" + step(k, t)
        shown = out
        Theme.liveColors = assembled(out)
    }
    function settle() {
        ticker.stop()
        shown = null
        Theme.liveColors = null
    }

    // ---- The cross-fade (session 27; components/ColorFade.qml). A change of colour that fades (`motion.blend_colors`, or
    // Dynamic Media Color's `fade`) is not stepped colour by colour: the gate holds the new tokens back, every window
    // takes a picture of itself, the tokens come in under the pictures and the pictures fade. The wheel blends of
    // Dynamic Media Color still step (below): they turn colours, which a cross-fade cannot.
    property bool holding: false
    property bool crossed: false
    // KURASHI_FADE_LOG=1: which colours started a cross-fade (an idle shell must start none: test-frame's idle check).
    readonly property bool logs: Quickshell.env("KURASHI_FADE_LOG") === "1"
    function gate(next) {
        if (cb.holding) return true                      // (a change while one is held: the release takes the latest)
        var was = cb.rest
        if (!was || !Theme.springOn) return false
        var nowTint = "" + (next["media.tint"] || ""), tinted = nowTint !== cb.tint
        var kind = "" + (next["media.blend"] || "fade")
        if (tinted ? kind !== "fade" : next["motion.blend_colors"] !== true) return false
        // (not for the material's ink alone: it arrives with the material's tiles, seconds after a change of look, and
        // the tiles themselves come in as a cut — a fade of every window for that one colour is a redraw of the idle
        // shell)
        var nf = flat(next), n = 0
        var why = []
        for (var k in nf) if (was[k] !== undefined && was[k] !== nf[k] && k.indexOf("texture.") !== 0) { n++; if (cb.logs) why.push(k + " " + was[k] + ">" + nf[k]) }
        if (n === 0) return false
        if (cb.logs) console.log("kurashi-fade gate", n, why.slice(0, 12).join(", "))
        if (ticker.running) settle()
        Theme.fadeMs = tinted ? Number(next["media.blend_ms"] || 1200) : Math.max(120, Number(next["motion.blend_colors_ms"] || 320))
        cb.holding = true
        cb.crossed = true
        Theme.fadeCapture++
        release.restart()
        return true
    }
    Component.onCompleted: Theme.fadeGate = cb.gate
    // (two frames for every window's picture to be taken; then the new tokens come in)
    Timer {
        id: release
        interval: 45
        onTriggered: {
            Theme.fadeShow++
            Theme.tokens = Theme.sourceTokens
            cb.holding = false
            Qt.callLater(function () { Theme.fadeRun++ })
        }
    }

    onTokensChanged: {
        var was = cb.rest, now = flat(tokens), nowTint = "" + (tokens["media.tint"] || "")
        var changed = nowTint !== cb.tint
        cb.rest = now
        cb.tint = nowTint
        if (!was) return                                    // the first theme: nothing to come from
        if (cb.crossed) { cb.crossed = false; return }      // (the cross-fade has this change)
        if (!changed) {
            if (ticker.running) { cb.to = now; return }     // a theme change mid-blend: the same way, to the new colours
            // I472 (K117): any other change of colour — a palette, the scheme, a look, the wallpaper's colours — fades
            // too, quickly, where `theme.motion.blend_colors` is on and motion is; a change of nothing but numbers cuts.
            if (tokens["motion.blend_colors"] !== true || !Theme.springOn || !differ(was, now)) return
            cb.from = was
            cb.to = now
            cb.kind = "fade"
            cb.turn = 0
            cb.runMs = Math.max(120, Number(tokens["motion.blend_colors_ms"] || 320))
            cb.startedAt = Date.now()
            paint(0)
            ticker.restart()
            return
        }
        var k = "" + (tokens["media.blend"] || "fade")
        if (k === "direct" || !Theme.springOn) return settle()
        cb.from = cb.shown || was
        cb.to = now
        cb.kind = k
        cb.turn = k === "fade" ? 0 : surfaceTurn()
        cb.runMs = Number(tokens["media.blend_ms"] || 1200) * (k === "fade" ? 1 : 1.5)
        cb.startedAt = Date.now()
        // Before the frame: what is on screen stays, the new tokens show only as the blend reaches them.
        paint(0)
        ticker.restart()
    }
    Timer {
        id: ticker
        interval: 33
        repeat: true
        onTriggered: {
            var t = Math.min(1, (Date.now() - cb.startedAt) / cb.runMs)
            if (t >= 1) return cb.settle()
            cb.paint(cb.ease(t))
        }
    }
}
