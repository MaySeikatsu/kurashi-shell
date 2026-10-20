import QtQuick
import "../core"

// An icon (K42): a Material Symbols Rounded ligature by `name` when the theme found the font, else the text
// `glyph` (Shōjiki: never a tofu box). `filled` uses the font's FILL axis. Sized by pixelSize like text.
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
    font.variableAxes: symbols ? { "FILL": filled ? 1 : 0, "wght": Theme.keycap ? 600 : 400, "opsz": 24 } : ({})
    color: Theme.fg
    renderType: Text.QtRendering
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    Accessible.ignored: true
}
