pragma Singleton
import QtQuick
import Quickshell

// The only reader of `theme.tokens` (rule 4). Fallbacks only cover a daemon that has not served a
// theme document (yet), so the window is never unstyled.
Singleton {
    readonly property var tokens: (Store.theme && Store.theme.tokens) ? Store.theme.tokens : ({})
    function tok(k, d) { var v = tokens[k]; return v === undefined ? d : v }
    function color(k, d) { return Qt.color(tok(k, d)) }
    // A colour token that may be missing (a palette without it): the given colour stands in.
    function colorOr(k, d) { var v = tokens[k]; return v === undefined ? d : Qt.color(v) }
    // QML Text has no per-script family list; pick the CJK family by script.
    function fam(t, f) { if (!f || f.length < 2) return ""; return /[　-ヿ一-鿿]/.test(t || "") ? f[1] : f[0] }

    readonly property var families: [tok("font.family", "Inter"), tok("font.family_jp", "Noto Sans CJK JP")]
    readonly property color fg: color("color.on_surface", "#e9e4d8")
    readonly property color dim: color("color.on_surface_variant", "#b9b2a6")
    readonly property color accent: color("color.accent", "#c9404b")
    // Text on the accent fill. Not `onAccent`: the frontend Theme found that name read back as black.
    readonly property color fgOnAccent: color("color.on_accent", "#fff6f1")
    readonly property color focusRing: color("focus.ring", "#c9404b")
    // Control height: button visuals take it; smaller controls enlarge their hit area to it (32 px floor).
    readonly property int controlH: tok("control.height", 32)
    readonly property color outline: color("color.outline", "#5a5560")
    readonly property color surface: color("color.surface", "#1b1a1e")
    readonly property color container: color("color.surface_container", "#252329")
    readonly property color containerHigh: color("color.surface_container_high", "#2f2c33")
    readonly property color error: color("color.error", "#e5766e")
    // Mod state marks (K25): the palette's status tokens; without them the accent and the dim text stand in.
    readonly property color statusOn: colorOr("color.status.on", accent)
    readonly property color statusOff: colorOr("color.status.off", dim)
    readonly property int pad: tok("space.md", 12)
    readonly property int gap: tok("space.sm", 8)
    readonly property int fs: tok("font.size.body", 13)
    readonly property int fsTitle: tok("font.size.title", 16)
    readonly property int rSm: tok("radius.sm", 6)
    readonly property int rLg: tok("radius.lg", 18)
    readonly property int rFull: tok("radius.full", 999)
    // Chrome (K42), as the shell's Theme: keycap = ink outline, ring and hard shadow; flat = all widths 0.
    readonly property bool keycap: tok("chrome.style", "flat") === "keycap"
    readonly property int outlineW: tok("chrome.outline", 0)
    readonly property int shadowDy: tok("chrome.shadow", 0)
    readonly property color line: color("chrome.line", "#121120")
    readonly property color ring: color("chrome.ring_color", "#e4e4ec")
    // K45 soft and line chrome (see the shell's Theme).
    readonly property color outlineColor: Qt.alpha(color("chrome.outline_color", "#121120"), tok("chrome.outline_alpha", 0))
    readonly property int softR: tok("chrome.soft", 0)
    readonly property int softDy: tok("chrome.soft_dy", 0)
    readonly property color softColor: Qt.alpha(color("chrome.soft_color", "#000000"), tok("chrome.soft_alpha", 0))
    readonly property real pressScale: tok("chrome.press_scale", 1)
    readonly property int iconFill: tok("icon.fill", 0)
    readonly property int iconWeight: tok("icon.weight", 400)
    // Tonal selection (I51): a selected choice is not an alarm.
    readonly property color selected: color("color.selected", "#4a3138")
    // Not `onSelected`: an `on…` name reads back black (the onAccent issue).
    readonly property color fgOnSelected: color("color.on_selected", "#e9e4d8")
    readonly property int wMedium: tok("font.weight.medium", 500)
    readonly property int wBold: tok("font.weight.bold", 700)
    readonly property string iconFamily: tok("font.icons", "")
    readonly property real overshoot: tok("motion.spring.overshoot", 0.6)
    readonly property bool springOn: tok("motion.spring.on", true)
    readonly property int stdMs: tok("motion.standard_ms", 220)
    readonly property real staleOpacity: tok("opacity.stale", 0.45)
}
