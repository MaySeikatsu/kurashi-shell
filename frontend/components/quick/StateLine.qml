import QtQuick
import "../../core"
import ".."

// The state under a switch or a list (W13): "connecting" while the request is pending; after a refusal or a timeout, the
// reason in red and a Retry control. Nothing at all while the request is idle.
Row {
    id: line
    property var req: null
    property string pendingText: ""
    readonly property bool failed: req !== null && req.failure !== ""
    visible: req !== null && (req.pending || failed)
    spacing: Theme.gap

    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        width: line.width - (retry.visible ? retry.width + Theme.gap : 0)
        wrapMode: Text.WordWrap
        color: line.failed ? Theme.error : Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: line.failed ? line.req.failure : line.pendingText
    }
    Button {
        id: retry
        visible: line.failed
        label: I18n.tr("island.quick.retry")
        onClicked: line.req.retry()
    }
}
