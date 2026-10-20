pragma Singleton
import QtQuick
import Quickshell

// The only reader of `theme.tokens` (rule 4). Components ask for tokens by name and never branch
// on theme/profile names. Fallbacks only cover a daemon that has not delivered the theme yet.
Singleton {
    readonly property var tokens: (Store.docs["theme"] && Store.docs["theme"].tokens) ? Store.docs["theme"].tokens : ({})
    function tok(k, d) { var v = tokens[k]; return v === undefined ? d : v }
    function color(k, d) { return Qt.color(tok(k, d)) }
    function bezier(k, d) { var c = tok(k, d); return [c[0], c[1], c[2], c[3], 1, 1] }
    // font.families is not exposed to QML Text; pick the CJK family by script.
    function fam(t, f) { if (!f || f.length < 2) return ""; return /[　-ヿ一-鿿]/.test(t || "") ? f[1] : f[0] }

    readonly property var families: [tok("font.family", "Inter"), tok("font.family_jp", "Noto Sans CJK JP")]
    readonly property color fg: color("color.on_surface", "#e9e4d8")
    readonly property color dim: color("color.on_surface_variant", "#b9b2a6")
    readonly property color accent: color("color.accent", "#c9404b")
    // Not `onAccent`: with an `accent` property beside it, `Theme.onAccent` read back as black
    // (qmltestrunner, Qt 6.11). The handler-prefix collision is the suspected cause, not verified.
    readonly property color fgOnAccent: color("color.on_accent", "#fff6f1")
    readonly property color error: color("color.error", "#e46962")
    readonly property color focusRing: color("focus.ring", "#c9404b")
    readonly property color outline: color("color.outline", "#5a5560")
    readonly property color surface: color("color.surface", "#1b1a1e")
    readonly property color surfaceAlpha: Qt.alpha(surface, tok("color.surface_alpha", 0.82))
    readonly property color container: color("color.surface_container", "#252329")
    // A panel's fill: the container at the material's opacity (solid = opaque, translucent and glass see through).
    readonly property color panel: Qt.alpha(container, tok("color.surface_alpha", 0.82))
    readonly property color containerHigh: color("color.surface_container_high", "#2f2c33")
    readonly property int barH: tok("bar.height", 36)
    // Control height. Visuals of buttons take it; smaller visuals enlarge their hit area to it (32 px floor).
    readonly property int controlH: tok("control.height", 32)
    readonly property int pad: tok("space.md", 12)
    readonly property int gap: tok("space.sm", 8)
    readonly property int xs: tok("space.xs", 4)
    readonly property int fs: tok("font.size.body", 13)
    readonly property int fsCaption: tok("font.size.caption", 11)
    readonly property int fsLabel: tok("font.size.label", 12)
    readonly property int fsTitle: tok("font.size.title", 16)
    readonly property int rSm: tok("radius.sm", 6)
    readonly property int rLg: tok("radius.lg", 18)
    readonly property int rFull: tok("radius.full", 999)
    readonly property int quickMs: tok("motion.quick_ms", 120)
    readonly property int stdMs: tok("motion.standard_ms", 220)
    readonly property int emphMs: tok("motion.emphasized_ms", 320)
    readonly property var enterCurve: bezier("motion.easing.enter", [0.05, 0.7, 0.1, 1.0])
    readonly property var continuousCurve: bezier("motion.easing.continuous", [0.4, 0.0, 0.2, 1.0])
    // Chrome (K42): a block is a flat fill, or a keycap — outline in `line`, a `ring` between outline and fill, and
    // a hard shadow straight down that it sinks into while pressed. All widths are 0 under flat chrome.
    readonly property bool keycap: tok("chrome.style", "flat") === "keycap"
    readonly property int outlineW: tok("chrome.outline", 0)
    readonly property int ringW: tok("chrome.ring", 0)
    readonly property int shadowDy: tok("chrome.shadow", 0)
    readonly property color line: color("chrome.line", "#121120")
    readonly property color ring: color("chrome.ring_color", "#e4e4ec")
    readonly property color selected: color("color.selected", "#4a3138")
    // Not `onSelected`: an `on…` name reads back black (the onAccent issue).
    readonly property color fgOnSelected: color("color.on_selected", "#e9e4d8")
    readonly property color secondary: color("color.secondary", "#5b7fa6")
    readonly property color tertiary: color("color.tertiary", "#8fa868")
    readonly property color warning: color("color.warning", "#e0a33b")
    function dataColor(i) { return color("color.data." + (((i - 1) % 4) + 1), "#5b7fa6") }
    readonly property int wRegular: tok("font.weight.regular", 400)
    readonly property int wMedium: tok("font.weight.medium", 500)
    readonly property int wBold: tok("font.weight.bold", 700)
    readonly property int fsDisplay: tok("font.size.display", 24)
    // Icons: Material Symbols Rounded by ligature name when installed ("" otherwise: Icon draws its glyph).
    readonly property string iconFamily: tok("font.icons", "")
    // Springs: arrivals overshoot by `overshoot` (Easing.OutBack amplitude); morphs that retarget mid-flight use
    // SpringAnimation with `spring`/`damping`. `springOn` false = motion off: snap.
    readonly property real overshoot: tok("motion.spring.overshoot", 0.6)
    readonly property bool springOn: tok("motion.spring.on", true)
    readonly property real spring: tok("motion.spring.spring", 4.0)
    readonly property real damping: tok("motion.spring.damping", 0.45)
    // How visible bar content stays while the daemon is away (reconnect veil).
    readonly property real staleOpacity: tok("opacity.stale", 0.45)
}
