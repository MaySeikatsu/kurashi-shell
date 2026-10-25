import QtQuick
import "../core"

// An icon (K42, K45): a Material Symbols ligature by `name` (Rounded, or Sharp under line chrome: `font.icons`) when the
// theme found the font, else the text `glyph` (Shōjiki: never a tofu box). The cut is the theme's: `icon.fill` fills
// every icon (keycap), `icon.weight` sets the stroke (600 keycap, 300 line); `filled` fills this one anyway (a lit state).
// Sized by pixelSize like text.
// W41 (row 446): the theme's family is the shell's subset (nix/icon-font.nix), which has the names in nix/icon-names.txt
// only; a name it lacks is drawn as letters, one glyph wide each. Such a name moves to the full Material Symbols family of
// the same cut (`font.icons_fallback`), and a name neither has draws the glyph, or a bullet when there is none: never letters.
Text {
    id: ic
    property string name: ""
    property string glyph: ""
    property bool filled: false
    property int size: Theme.fs + 4
    // The font that draws the name: 0 the theme's icon family, 1 the full family of the same cut, 2 neither (the glyph).
    // Only `settle()` raises it, and a new name starts again at 0.
    property int tier: 0
    readonly property string fallbackFamily: Theme.iconFamilyFallback
    readonly property string drawFamily: tier === 1 ? fallbackFamily : Theme.iconFamily
    readonly property bool symbols: name !== "" && drawFamily !== "" && tier < 2
    text: symbols ? name : (glyph !== "" ? glyph : (name !== "" && Theme.iconFamily !== "" ? "•" : ""))
    font.family: symbols ? drawFamily : Theme.fam(glyph, Theme.families)
    font.pixelSize: symbols ? size : Math.round(size * 0.8)
    font.variableAxes: symbols ? { "FILL": filled || Theme.iconFill > 0 ? 1 : 0, "wght": Theme.iconWeight, "opsz": 24 } : ({})
    color: Theme.fg
    renderType: Text.QtRendering
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    Accessible.ignored: true

    // A ligature is one glyph wide (`size`, measured: 40 px at 40 px); a name the family lacks is one glyph per letter,
    // so 1.5 × size tells them apart for every name of two or more letters. Handlers, not bindings: the width depends on
    // the family the tier picks.
    function settle() {
        if (symbols && contentWidth > 1.5 * size)
            tier = tier === 0 && fallbackFamily !== "" ? 1 : 2
    }
    onContentWidthChanged: settle()
    // A new name or a new theme family starts again at 0. The layout of the new text may not have run yet; the check
    // after the event loop reads it.
    function retry() {
        tier = 0
        Qt.callLater(settle)
    }
    readonly property string families: Theme.iconFamily + "|" + fallbackFamily
    onNameChanged: retry()
    onFamiliesChanged: retry()
}
