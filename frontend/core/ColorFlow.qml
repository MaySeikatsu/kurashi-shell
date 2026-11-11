pragma Singleton
import QtQml
import QtQuick
import Quickshell

// Colour in motion (session 28, docs/ux/colour-flow.md; `theme.colors.flow.*`, the daemon's `flow.*` tokens): one
// clock for every colour that moves — the chrome's gradient (Wash takes `phase` and `patternIndex` as uniforms: the
// shader moves it, nothing is recoloured in QML), the frame's outline and what is joined to it, the frame's glow and
// the Glow chrome's light (Theme hands out `line` and `glow` in place of the still colours).
// Ma: the clock runs only while the flow is on AND its moment is there (`flow.when`: always; while a card, the
// launcher or a sidebar is open; while music plays). Stopped, the phase stays where it is — the colours rest where
// they were, no jump back — and nothing draws. The daemon turns `flow.on` off under reduced motion and the motion
// profile None.
Singleton {
    id: cf
    readonly property bool on: Theme.tok("flow.on", false) === true
    readonly property string when: String(Theme.tok("flow.when", "active"))
    readonly property string pattern: String(Theme.tok("flow.pattern", "drift"))
    readonly property string colours: String(Theme.tok("flow.colours", "palette"))
    readonly property real speed: Math.max(0.25, Math.min(4, Number(Theme.tok("flow.speed", 1)) || 1))
    readonly property bool gradientOn: on && Theme.tok("flow.gradient", true) === true
    readonly property bool lineOn: on && Theme.tok("flow.outline", true) === true
    readonly property bool glowOn: on && Theme.tok("flow.glow", true) === true

    // What is open: the Stage's card, a tray menu, the launcher (runtime.ui), and the surfaces that say so themselves
    // (a sidebar: `hold(±1)`).
    readonly property var ui: (Store.docs && Store.docs["runtime.ui"]) || ({})
    property int holds: 0
    function hold(d) { holds = Math.max(0, holds + d) }
    readonly property bool busy: (ui.panel || "") !== "" || (ui.tray || "") !== "" || ui.launcher === true || holds > 0
    // Music: the media document, watched only while the flow waits for it.
    readonly property bool wantsMedia: on && when === "media"
    readonly property var media: wantsMedia && Store.docs ? Store.docs["svc.media"] : null
    readonly property bool playing: !!media && (media.status === "playing" || media.playing === true
        || (media.active && media.active.status === "playing"))
    readonly property bool running: on && (when === "always" || (when === "active" && busy) || (when === "media" && playing))

    // The clock: 0 … 1, one round in 12 s at speed 1.
    // B99 (session 29, measured on the user's session while music played: the shell at 125 % of a core, eight windows
    // redrawn at the display's rate, niri at 40 %): the clock steps, it is not an animation. Every colour that flows is
    // a full redraw of every window that shows it (the gradient is a shader over each washed surface, and each commit
    // makes the compositor blur again), and a slow drift does not need the display's rate: 15 steps a second at the
    // slow speeds (under 2 levels of 255 a step, a pixel of the gradient's drift), the display's rate only at speed 2
    // and up. A Timer alone does not run the animation driver (Qt parks a lone pause on a single shot), so between steps
    // nothing wakes.
    property real phase: 0
    readonly property int stepMs: Math.round(1000 / Math.min(60, Math.max(15, 30 * speed)))
    // A surface in motion (a card, a sidebar, the launcher opening or closing: components/motion/SurfaceForm.qml) has
    // the frame budget to itself: the clock rests for that moment and goes on from where it stood. A count, with a
    // watch that clears it should a surface go without giving its rest back.
    property int rests: 0
    function rest(d) { rests = Math.max(0, rests + d) }
    property Timer restWatch: Timer { interval: 4000; running: cf.rests > 0; onTriggered: cf.rests = 0 }
    property Timer clock: Timer {
        interval: cf.stepMs
        repeat: true
        running: cf.running && cf.rests === 0
        onTriggered: { var p = cf.phase + cf.stepMs * cf.speed / 12000; cf.phase = p - Math.floor(p) }
    }
    // The gradient's pattern for wash.frag (0 = still).
    readonly property int patternIndex: !gradientOn ? 0 : pattern === "breathe" ? 2 : pattern === "cycle" ? 3 : pattern === "chase" ? 4 : 1

    // The colours the line and the glow run through, by `flow.colours`.
    readonly property var stops: colours === "tones"
        ? [Qt.darker(Theme.accent, 1.35), Theme.accent, Qt.lighter(Theme.accent, 1.45), Theme.accent]
        : [Theme.accent, Theme.secondary, Theme.tertiary]
    // (a colour not there yet — the theme between two documents — leaves the other as it is)
    function mix(a, b, t) { if (!a || !b) return a || b || Qt.rgba(0, 0, 0, 0); return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }
    // The colour at `p` (0 … 1, wraps) of the round.
    function round(p) {
        p = p - Math.floor(p)
        if (colours === "rainbow") return Qt.hsla(p, 0.72, Theme.darkScheme ? 0.66 : 0.46, 1)
        var n = stops.length, x = p * n, i = Math.floor(x) % n, f = x - Math.floor(x)
        f = f * f * (3 - 2 * f)
        return mix(stops[i], stops[(i + 1) % n], f)
    }
    // The line's and the glow's colour now, from a still colour `base`:
    //   drift, cycle  through the round
    //   breathe       the still colour swelling toward the round's colour and back, twice a round
    //   chase         the still colour, lit for a moment as the light passes (three times a round)
    function tint(base) {
        if (pattern === "breathe") return mix(base, round(phase), 0.5 - 0.5 * Math.cos(4 * Math.PI * phase))
        if (pattern === "chase") {
            var k = Math.pow(Math.max(0, Math.cos(2 * Math.PI * (phase * 3 - Math.floor(phase * 3)))), 6)
            return mix(base, Qt.lighter(round(phase), 1.5), k)
        }
        return round(phase)
    }
}
