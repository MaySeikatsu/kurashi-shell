import QtQuick
import qs.core

// Inside a configured folder: the way down to the current one (root › sub › …) and the folders under it, with their
// picture counts (`wallpaper.thumbs` children). A crumb goes back up to it, a folder opens; Backspace in the grid goes up
// one. Shown only while there is a way down or a folder below.
ChipRow {
    id: crumbs
    readonly property var model: host ? host.crumbModel() : []
    visible: model.length > 0
    Accessible.role: Accessible.Grouping
    Repeater {
        model: crumbs.model
        delegate: PickButton {
            required property var modelData
            readonly property bool here: modelData.here === true
            objectName: "wall-crumb-" + modelData.label.split(" ")[0]
            label: (modelData.kind === "sub" ? "▸ " : "") + modelData.label
            selected: here
            // Changing the folder rebuilds this row, which destroys the chip that asked: the grid takes the focus.
            onActivated: {
                crumbs.host.folder = modelData.path
                crumbs.host.later(crumbs.host.focusGrid)
            }
        }
    }
}
