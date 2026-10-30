import QtQuick
import "../core"

// The one page-header pattern (UX review R.2 item 18): the page title in Theme.fg, the sections
// below it as dim labels. Accent is for actions and state, never for text.
Text {
    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
    color: Theme.fg
    font.pixelSize: Theme.fsTitle
    font.family: Theme.fam(text, Theme.families)
    wrapMode: Text.WordWrap
}
