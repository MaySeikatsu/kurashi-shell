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
    // A panel's fill: the container at the material's opacity (solid = opaque, translucent sees through).
    readonly property color panel: Qt.alpha(container, tok("color.surface_alpha", 0.82))
    // The compositor's blur behind the chrome (`theme.material.blur`): translucent only, and only while the switch is on and
    // the compositor can (the daemon's token, schema v7). Every window's BackgroundEffect.blurRegion is empty otherwise.
    readonly property bool blur: tok("blur", false) === true
    // `theme.shape.corners = squircle` (I281): every shape draws its quarter corners as squircle curves (core/corner.js);
    // a pill's round end stays round.
    // The value is the squircle's handle ratio (`theme.shape.squircle`, token `shape.squircle_k`, I300) and 0 for round
    // corners: true-ish exactly when the look is a squircle one, and every path built with it redraws when the curve moves.
    readonly property real squircleK: tok("shape.squircle_k", 0.88)
    readonly property real squircle: tok("shape.corner", "rounded") === "squircle" ? squircleK : 0
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
    // K74 (I269): the radius of a corner that lies `inset` px inside a corner of `outer` — concentric with it, so curves
    // inside one another keep one distance all round (0 once the inset is the radius or more).
    function nested(outer, inset) { return Math.max(0, Math.round(outer - inset)) }
    readonly property int quickMs: tok("motion.quick_ms", 120)
    readonly property int stdMs: tok("motion.standard_ms", 220)
    readonly property int emphMs: tok("motion.emphasized_ms", 320)
    readonly property var enterCurve: bezier("motion.easing.enter", [0.05, 0.7, 0.1, 1.0])
    readonly property var continuousCurve: bezier("motion.easing.continuous", [0.4, 0.0, 0.2, 1.0])
    // Chrome (K42): a block is a flat fill, or a keycap — outline in `line`, a `ring` between outline and fill, and
    // a hard shadow straight down that it sinks into while pressed. All widths are 0 under flat chrome.
    // Keycap-only details (the ring, the sink): derived from the ring width, never from the chrome's name (rule 4).
    readonly property bool keycap: ringW > 0
    readonly property int outlineW: tok("chrome.outline", 0)
    readonly property int ringW: tok("chrome.ring", 0)
    readonly property int shadowDy: tok("chrome.shadow", 0)
    readonly property color line: color("chrome.line", "#121120")
    readonly property color ring: color("chrome.ring_color", "#e4e4ec")
    // K45: soft and line chrome. Read the widths and colours, never `chromeStyle` to pick a look (rule 4); the
    // style name is for logs and tests.
    readonly property string chromeStyle: tok("chrome.style", "flat")
    readonly property color outlineColor: Qt.alpha(color("chrome.outline_color", "#121120"), tok("chrome.outline_alpha", 0))
    readonly property int softR: tok("chrome.soft", 0)
    readonly property int softDy: tok("chrome.soft_dy", 0)
    // K67 (docs/ux/shadows.md): the vector every shadow falls along — the user's strength and direction, or away from the
    // light — for the hard shadow and its sink as for the soft shadow's offset. `shadowDy`/`softDy` stay the look's own
    // lengths: the room a block keeps for its shadow (layout), which never moves with the setting. Fallbacks are today's.
    readonly property real shadowX: tok("shadow.dx", 0)
    readonly property real shadowY: tok("shadow.dy", shadowDy + softDy)
    readonly property real shadowAlpha: tok("shadow.alpha_scale", 1)
    // The hard shadow's vector in whole px (a crisp edge), 0, 0 for a chrome without one (or strength 0: no sink then).
    readonly property int sinkX: shadowDy > 0 ? Math.round(shadowX) : 0
    readonly property int sinkY: shadowDy > 0 ? Math.round(shadowY) : 0
    readonly property color softColor: Qt.alpha(color("chrome.soft_color", "#000000"),
        Math.min(1, tok("chrome.soft_alpha", 0) * shadowAlpha))
    readonly property real pressScale: tok("chrome.press_scale", 1)
    // Bar groups stand as blocks of their own (keycap, soft, line) instead of sitting on one strip (flat).
    readonly property bool groups: tok("chrome.groups", false)
    // W25: the decor pack's frame (`decor.frame`), a name FrameHost loads as data ("" = none; rule 4).
    readonly property string frame: tok("decor.frame", "")
    readonly property int iconFill: tok("icon.fill", 0)
    readonly property int iconWeight: tok("icon.weight", 400)
    // Row 125: a block casts a shadow of either kind (bar groups float), or is an outlined box with no fill (line).
    readonly property bool lifted: shadowDy > 0 || softR > 0
    readonly property bool boxed: outlineW > 0 && !lifted
    // `theme.frame_outline` (I303): a line along the frame's inner edge and the sides of what joins it (bars' edges, the
    // dock, sidebars, edge groups), in the chrome's own outline — its ink, or a hairline where the chrome draws none. The
    // daemon resolves `auto` per chrome (`frame.outline`); without it, the rule the boxed chrome always drew.
    readonly property bool frameOutline: tok("frame.outline", boxed) === true
    readonly property int frameOutlineW: frameOutline ? Math.max(1, outlineW) : 0
    // Its ink and stroke (`theme.frame_outline_ink` / `_stroke`, looks set them: kami's is the text's ink, sketched as its
    // blocks): the chrome's outline, the text's ink at its blocks' 0.85, or the accent; one even line or the sketch.
    readonly property string frameInk: tok("frame.outline_ink", "outline")
    readonly property color frameOutlineColor: frameInk === "text" ? Qt.alpha(fg, 0.85) : frameInk === "accent" ? accent
        : (outlineW > 0 ? outlineColor : outline)
    readonly property bool frameSketch: tok("frame.outline_stroke", "line") === "sketch"
    // Row 130: the dim layer behind a modal (polkit, later the session keys): the palette's scrim role at 40 %.
    readonly property color scrim: Qt.alpha(color("color.scrim", "#000000"), 0.4)
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
    // Icons: the shell's subset (Kurashi Symbols), else Material Symbols, by ligature name ("" otherwise: Icon draws its
    // glyph). The fallback is the full family of the same cut, for a name the subset lacks (W41, rows 445/446/458).
    readonly property string iconFamily: tok("font.icons", "")
    readonly property string iconFamilyFallback: tok("font.icons_fallback", "")
    // Springs: arrivals overshoot by `overshoot` (Easing.OutBack amplitude); morphs that retarget mid-flight use
    // SpringAnimation with `spring`/`damping`. `springOn` false = motion off: snap.
    readonly property real overshoot: tok("motion.spring.overshoot", 0.6)
    readonly property bool springOn: tok("motion.spring.on", true)
    readonly property real spring: tok("motion.spring.spring", 4.0)
    readonly property real damping: tok("motion.spring.damping", 0.45)
    // K74: how surfaces move — "timed" (expressive: Caelestia's curves; a surface grows out of its edge on `openCurve` over
    // `openMs`, folds back on `closeCurve` over `closeMs`, its content fades on `effectsCurve`), "spring" (calm, lively:
    // the springs above) or "none" (cuts). Curves are `easing.bezierCurve` lists (several segments, ending at 1, 1).
    readonly property string motionKind: tok("motion.kind", springOn ? "spring" : "none")
    readonly property bool timed: motionKind === "timed"
    readonly property int openMs: tok("motion.timed.open_ms", 500)
    readonly property int closeMs: tok("motion.timed.close_ms", 400)
    readonly property int fastMs: tok("motion.timed.fast_ms", 350)
    readonly property int effectsMs: tok("motion.timed.effects_ms", 200)
    readonly property var openCurve: tok("motion.timed.open_curve", [0.38, 1.21, 0.22, 1, 1, 1])
    readonly property var closeCurve: tok("motion.timed.close_curve",
        [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1])
    readonly property var fastCurve: tok("motion.timed.fast_curve", [0.42, 1.67, 0.21, 0.9, 1, 1])
    readonly property var effectsCurve: tok("motion.timed.effects_curve", [0.34, 0.8, 0.34, 1, 1, 1])
    // How visible bar content stays while the daemon is away (reconnect veil).
    readonly property real staleOpacity: tok("opacity.stale", 0.45)
    readonly property int longMs: tok("motion.long_ms", 500)

    // K59 (docs/ux/texture.md, DESIGN-SYSTEM "Texture and light"): the material's relief and its light, as the daemon
    // resolves them. A Relief exists only while a shell scope shades (`texShell`) or the everything overlay does
    // (`texOverlay`), and a tile is there (`texOn`): nothing is made for a theme without a texture (Ma).
    readonly property string texMap: tok("texture.map", "")
    // The ink coverage map (alpha only): "" when the material prints no ink.
    readonly property string texInkMap: tok("texture.ink_map", "")
    readonly property real texAmp: tok("texture.amp", 0)
    readonly property bool texOn: texMap !== "" && texAmp > 0
    readonly property bool texShell: texOn && tok("texture.shell", false) === true
    readonly property bool texOverlay: texOn && tok("texture.overlay", false) === true
    // The relief shades text and icons too (drawn over the content) instead of sitting under it.
    readonly property bool texText: tok("texture.text", false) === true
    readonly property real texTilePx: tok("texture.tile_px", 0)
    readonly property real texTileLogical: tok("texture.tile_logical", 0)
    readonly property real texScale: tok("texture.scale", 1)
    readonly property real texGloss: tok("texture.gloss", 0)
    readonly property real texShininess: tok("texture.shininess", 1)
    readonly property color texInk: color("texture.ink", "#000000")
    readonly property real texInkAlpha: tok("texture.ink_alpha", 0)
    readonly property string lightMode: tok("light.mode", "static")
    // Unit vector toward the light (x right, y down, z toward the viewer); a daytime sun or the static angle.
    readonly property var lightDirToken: tok("light.dir", [0, 0, 1])
    readonly property color lightColor: color("light.color", "#ffffff")
    readonly property real lightHeight: tok("light.height_px", 60)

    // K61 (wave 32): depth, relief shadows (`texHeightMap` "" while they are off), the dark ground's balance, controls,
    // how the sheet sits on moving surfaces, and the spotlight (its pin as fractions of the output, its beam in degrees).
    readonly property real texDepth: tok("texture.depth", 1)
    readonly property real texShadow: tok("texture.shadow", 0)
    readonly property string texHeightMap: tok("texture.height_map", "")
    readonly property real texReliefPx: tok("texture.relief_px", 0)
    readonly property real texLit: tok("texture.lit", 1)
    readonly property bool texControls: texShell && tok("texture.controls", false) === true
    // "carried" | "fixed" | "separate"
    readonly property string texSheet: tok("texture.sheet", "carried")
    readonly property var lightPin: tok("light.pin", null)
    readonly property real lightBeam: tok("light.beam", 35)

    // K62: the pen. `penLine`: "solid" | "dotted" | "dashed" | "broken" | "rough"; the modifiers 0..1, for outlines and
    // (through a layer over a block's content) for text and icons. Values in effect: high contrast forces them off.
    readonly property string penLine: tok("pen.line", "solid")
    readonly property real penPressure: tok("pen.pressure", 0)
    readonly property real penBreaks: tok("pen.breaks", 0)
    readonly property real penFade: tok("pen.fade", 0)
    readonly property real penWobble: tok("pen.wobble", 0)
    readonly property real penTextPressure: tok("pen.text_pressure", 0)
    readonly property real penTextBreaks: tok("pen.text_breaks", 0)
    readonly property real penTextFade: tok("pen.text_fade", 0)
    readonly property real penTextWobble: tok("pen.text_wobble", 0)
    // Some outline modifier or line style is in effect: outlines are drawn by the pen, not as straight borders.
    readonly property bool penOutline: penLine !== "solid" || penPressure > 0 || penBreaks > 0 || penFade > 0 || penWobble > 0
    // The frame outline goes through the pen when the pen is in effect or the outline is sketched (pen.js `sketch`).
    readonly property bool framePen: penOutline || frameSketch
    readonly property string framePenLine: frameSketch ? "sketch" : penLine
    readonly property bool penText: penTextPressure > 0 || penTextBreaks > 0 || penTextFade > 0 || penTextWobble > 0
}
