import QtQuick
import Quickshell
import qs.core

// The reason a control is inert, as a small tip (docs/ux/webdock.md "Forced/inert", "Keyboard and a11y"): it shows after
// a short rest on the control, or while the control has keyboard focus (`shown`). The tip is a PopupWindow beside the
// control, not a child of it: the strip's window is only as thick as the strip, so a wider tip would be cut off there.
// It is click-through, and it exists only while shown (Ma: nothing is made while the tip is hidden). The app dock's tip
// (frontend/surfaces/Dock.qml) works the same way.
Item {
    id: tip
    property Item target: null
    property string text: ""
    property bool shown: false
    // The dock's edge: the tip stands on the screen side of the strip, centred on the control across it.
    property string edge: "right"
    readonly property int gap: 6
    // Set once the rest has lasted: the popup is made then, and unmade as soon as `shown` drops.
    property bool open: false

    width: 0
    height: 0
    onShownChanged: if (!shown) open = false

    Timer {
        interval: 400
        running: tip.shown && tip.text !== "" && tip.target !== null
        onTriggered: tip.open = true
    }

    LazyLoader {
        active: tip.open && tip.text !== "" && tip.target !== null

        PopupWindow {
            id: pop
            // A PopupWindow starts hidden in Quickshell: the tip is shown as soon as it is made (the app dock does the same).
            visible: tip.text !== ""
            anchor.item: tip.target
            anchor.edges: tip.edge === "right" ? Edges.Left : (tip.edge === "left" ? Edges.Right
                : (tip.edge === "bottom" ? Edges.Top : Edges.Bottom))
            anchor.gravity: anchor.edges
            anchor.margins.left: tip.edge === "right" ? -tip.gap : 0
            anchor.margins.right: tip.edge === "left" ? -tip.gap : 0
            anchor.margins.top: tip.edge === "bottom" ? -tip.gap : 0
            anchor.margins.bottom: tip.edge === "top" ? -tip.gap : 0
            implicitWidth: box.width
            implicitHeight: box.height
            color: "transparent"
            mask: Region {}
            Component.onCompleted: if (Quickshell.env("KURASHI_WEBDOCK_DEBUG") === "1") console.log("webdock-debug tip", tip.text)

            Rectangle {
                id: box
                width: label.implicitWidth + 2 * Theme.gap
                height: label.implicitHeight + Theme.gap
                radius: Theme.rSm
                color: Theme.panel
                border.width: 1
                border.color: Theme.outline
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: tip.text
                    color: Theme.fg
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(label.text, Theme.families)
                }
            }
        }
    }
}
