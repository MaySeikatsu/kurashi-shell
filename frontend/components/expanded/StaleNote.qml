import QtQuick
import "../../core"

// "As of 09:10" under an expanded view whose face the daemon marks stale (runtime.island.main.stale_at, K30): what the
// view shows is true only as of that time, so it says so instead of pretending. Nothing while the face is fresh.
// It reads the island's document itself (one more subscriber to the same doc, refcounted), and only while it is shown.
Text {
    id: note
    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
    property string face: ""
    Watch { doc: "runtime.island.main" }
    readonly property var at: ((Store.docs["runtime.island.main"] || ({})).stale_at || ({}))[face]
    visible: at !== undefined && at !== null
    width: parent.width
    wrapMode: Text.WordWrap
    color: Theme.dim
    font.pixelSize: Theme.fsCaption
    font.family: Theme.fam(text, Theme.families)
    text: visible ? I18n.tr("island.stale").replace("{t}", Qt.formatTime(new Date(at), "hh:mm")) : ""
}
