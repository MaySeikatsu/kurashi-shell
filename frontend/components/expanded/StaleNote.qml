import QtQuick
import "../../core"
import ".."

// "As of 09:10" under an expanded view whose face the daemon marks stale (runtime.island.main.stale_at, K30): what the
// view shows is true only as of that time, so it says so instead of pretending. Nothing while the face is fresh.
// It reads the island's document itself (one more subscriber to the same doc, refcounted), and only while it is shown.
Label {
    id: note
    property string face: ""
    Watch { doc: "runtime.island.main" }
    readonly property var at: ((Store.docs["runtime.island.main"] || ({})).stale_at || ({}))[face]
    visible: at !== undefined && at !== null
    width: parent.width
    wrapMode: Text.WordWrap
    dim: true
    font.pixelSize: Theme.fsCaption
    text: visible ? I18n.tr("island.stale").replace("{t}", Qt.formatTime(new Date(at), "hh:mm")) : ""
}
