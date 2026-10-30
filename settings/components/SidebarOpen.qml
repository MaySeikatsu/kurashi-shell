import QtQuick
import "../core"

// Under "Open from the bar" (I154; K71 folded the bar buttons into the zones): the sidebars open from here too — "Open now" for each side — and the line naming the
// keys the Home-Manager module binds by default (they need its niri binds file included; Settings cannot see niri's
// binds, so it names the defaults and where they come from). The left one only while the left sidebar has tabs.
Column {
    id: so
    spacing: Theme.gap
    width: parent ? parent.width : 400
    objectName: "sidebar-open"
    readonly property var tabs: Store.valueOf("sidebar.left.sections")
    readonly property bool hasLeft: Array.isArray(so.tabs) && so.tabs.length > 0
    property string error: ""

    function open(side) {
        Store.act("sidebar.open", { side: side }, function (m) {
            so.error = m.t === "done" ? "" : Store.actError(m, "sidebar.header.failed")
        })
    }

    Flow {
        width: so.width
        spacing: Theme.gap
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            height: Theme.controlH
            verticalAlignment: Text.AlignVCenter
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("sidebar.open_now")
        }
        Button {
            objectName: "sidebar-open-right"
            label: I18n.tr("action.sidebar.right.toggle")
            enabled: Store.live
            onClicked: so.open("right")
        }
        Button {
            objectName: "sidebar-open-left"
            visible: so.hasLeft
            label: I18n.tr("action.sidebar.left.toggle")
            enabled: Store.live
            onClicked: so.open("left")
        }
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        width: so.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fs - 1
        font.family: Theme.fam(text, Theme.families)
        text: I18n.fmt("sidebar.keys", { right: "Mod+Shift+N", left: "Mod+A" })
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: so.error !== ""
        width: so.width
        wrapMode: Text.WordWrap
        color: Theme.error
        font.pixelSize: Theme.fs - 1
        font.family: Theme.fam(text, Theme.families)
        text: "⊘ " + so.error
    }
}
