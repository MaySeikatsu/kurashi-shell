pragma Singleton
import QtQuick
import Quickshell

// The only reader of `theme.tokens` (rule 4). Components ask for tokens by name and never branch
// on theme/profile names. Fallbacks only cover a daemon that has not delivered the theme yet.
Singleton {
    readonly property var tokens: (Store.theme && Store.theme.tokens) ? Store.theme.tokens : ({})
    function tok(k, d) { var v = tokens[k]; return v === undefined ? d : v }
    function color(k, d) { return Qt.color(tok(k, d)) }
    function bezier(k, d) { var c = tok(k, d); return [c[0], c[1], c[2], c[3], 1, 1] }
    // font.families is not exposed to QML Text; pick the CJK family by script.
    function fam(t, f) { if (!f || f.length < 2) return ""; return /[　-ヿ一-鿿]/.test(t || "") ? f[1] : f[0] }

    readonly property var families: [tok("font.family", "Inter"), tok("font.family_jp", "Noto Sans CJK JP")]
    readonly property color fg: color("color.on_surface", "#e9e4d8")
    readonly property color dim: color("color.on_surface_variant", "#b9b2a6")
    readonly property color accent: color("color.accent", "#c9404b")
    readonly property color outline: color("color.outline", "#5a5560")
    readonly property color surface: color("color.surface", "#1b1a1e")
    readonly property color surfaceAlpha: Qt.alpha(surface, tok("color.surface_alpha", 0.82))
    readonly property color container: color("color.surface_container", "#252329")
    readonly property color containerHigh: color("color.surface_container_high", "#2f2c33")
    readonly property int barH: tok("bar.height", 36)
    readonly property int pad: tok("space.md", 12)
    readonly property int gap: tok("space.sm", 8)
    readonly property int fs: tok("font.size.body", 13)
    readonly property int fsTitle: tok("font.size.title", 16)
    readonly property int rSm: tok("radius.sm", 6)
    readonly property int rLg: tok("radius.lg", 18)
    readonly property int rFull: tok("radius.full", 999)
    readonly property int stdMs: tok("motion.standard_ms", 220)
    readonly property int emphMs: tok("motion.emphasized_ms", 320)
    readonly property var enterCurve: bezier("motion.easing.enter", [0.05, 0.7, 0.1, 1.0])
    // How visible bar content stays while the daemon is away (reconnect veil).
    readonly property real staleOpacity: tok("opacity.stale", 0.45)
}
