import QtQuick
import "../../core"
import ".."

// The island card for a face without an expanded view (mod faces, or none): its title. The Close
// control under it belongs to the Stage.
Label {
    width: parent.width
    font.pixelSize: Theme.fsTitle
    text: I18n.tr("frontend.stage.title")
}
