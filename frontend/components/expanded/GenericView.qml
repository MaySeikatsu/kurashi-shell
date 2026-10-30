import QtQuick
import "../../core"

// The island card for a face without an expanded view (mod faces, or none): its title. The Close
// control under it belongs to the Stage.
Text {
    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
    width: parent.width
    color: Theme.fg
    font.pixelSize: Theme.fsTitle
    font.family: Theme.fam(text, Theme.families)
    text: I18n.tr("frontend.stage.title")
}
