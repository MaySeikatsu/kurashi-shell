import QtQuick
import "../../core"

// A line of the Motion page's own controls, set as every Settings text is (pixel looks hint fully, the family by script).
// `small` is the help size (fs − 2).
Text {
    property bool small: false
    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
    antialiasing: !Theme.pixelType
    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
    color: Theme.fg
    wrapMode: Text.WordWrap
    font.pixelSize: small ? Theme.fs - 2 : Theme.fs
    font.family: Theme.fam(text, Theme.families)
}
