pragma Singleton
import QtQuick
import Quickshell

// The only reader of `theme.tokens` (rule 4). Fallbacks only cover a daemon that has not served a
// theme document (yet), so the window is never unstyled.
Singleton {
    readonly property var tokens: (Store.theme && Store.theme.tokens) ? Store.theme.tokens : ({})
    function tok(k, d) { var v = tokens[k]; return v === undefined ? d : v }
    function color(k, d) { return Qt.color(tok(k, d)) }
    // QML Text has no per-script family list; pick the CJK family by script.
    function fam(t, f) { if (!f || f.length < 2) return ""; return /[　-ヿ一-鿿]/.test(t || "") ? f[1] : f[0] }

    readonly property var families: [tok("font.family", "Inter"), tok("font.family_jp", "Noto Sans CJK JP")]
    readonly property color fg: color("color.on_surface", "#e9e4d8")
    readonly property color dim: color("color.on_surface_variant", "#b9b2a6")
    readonly property color accent: color("color.accent", "#c9404b")
    readonly property color outline: color("color.outline", "#5a5560")
    readonly property color surface: color("color.surface", "#1b1a1e")
    readonly property color container: color("color.surface_container", "#252329")
    readonly property color containerHigh: color("color.surface_container_high", "#2f2c33")
    readonly property color error: color("color.error", "#e5766e")
    readonly property int pad: tok("space.md", 12)
    readonly property int gap: tok("space.sm", 8)
    readonly property int fs: tok("font.size.body", 13)
    readonly property int fsTitle: tok("font.size.title", 16)
    readonly property int rSm: tok("radius.sm", 6)
    readonly property int rLg: tok("radius.lg", 18)
    readonly property int rFull: tok("radius.full", 999)
    readonly property real staleOpacity: tok("opacity.stale", 0.45)
}
