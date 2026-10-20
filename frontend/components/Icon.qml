import QtQuick
import "../core"

// An icon (K42, K45): a Material Symbols ligature by `name` (Rounded, or Sharp under line chrome: `font.icons`) when the
// theme found the font, else the text `glyph` (Shōjiki: never a tofu box). The cut is the theme's: `icon.fill` fills
// every icon (keycap), `icon.weight` sets the stroke (600 keycap, 300 line); `filled` fills this one anyway (a lit state).
// Sized by pixelSize like text.
Text {
    id: ic
    property string name: ""
    property string glyph: ""
    property bool filled: false
    property int size: Theme.fs + 4
    readonly property bool symbols: Theme.iconFamily !== "" && name !== ""
    text: symbols ? name : glyph
    font.family: symbols ? Theme.iconFamily : Theme.fam(glyph, Theme.families)
    font.pixelSize: symbols ? size : Math.round(size * 0.8)
    font.variableAxes: symbols ? { "FILL": filled || Theme.iconFill > 0 ? 1 : 0, "wght": Theme.iconWeight, "opsz": 24 } : ({})
    color: Theme.fg
    renderType: Text.QtRendering
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    Accessible.ignored: true
}
