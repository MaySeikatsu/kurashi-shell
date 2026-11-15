import QtQuick
import "../core"

// The shell's text (K154, rule 10): one place for how a line of copy is drawn — the look's type (pixel looks render
// natively, unsmoothed, fully hinted), the body size, the text ink, and the family by script (Latin or Japanese).
// `dim` draws the secondary ink. Set `font.pixelSize: Theme.fsCaption` and the like for other steps of the scale; never
// a number.
Text {
    property bool dim: false
    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
    antialiasing: !Theme.pixelType
    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
    color: dim ? Theme.dim : Theme.fg
    font.pixelSize: Theme.fs
    font.family: Theme.fam(text, Theme.families)
}
