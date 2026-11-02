import QtQuick
import "../../core"
import ".."

// Tabs of the curve editor (Cubic · Spring · Steps · Presets): WAI-ARIA tabs — Tab enters at the open one, Left and Right
// open the neighbour, Home and End the first and last. Opening a tab changes the view, never the value.
Row {
    id: tb
    // [{id, label (translated)}]
    property var tabs: []
    property string current: ""
    // objectName prefix: "<prefix>:<id>" per tab (the settings test reaches them by name).
    property string prefix: ""
    signal activated(string id)
    spacing: 2
    Accessible.role: Accessible.PageTabList

    function go(i) {
        if (i < 0 || i >= tb.tabs.length) return
        tb.activated(tb.tabs[i].id)
        var it = rep.itemAt(i)
        if (it) it.forceActiveFocus()
    }

    Repeater {
        id: rep
        model: tb.tabs
        delegate: RoundBox {
            id: tab
            required property var modelData
            required property int index
            readonly property bool on: modelData.id === tb.current
            objectName: tb.prefix + ":" + modelData.id
            implicitWidth: cap.implicitWidth + 2 * Theme.pad
            implicitHeight: 28
            radius: Theme.rSm
            color: on ? Theme.container : "transparent"
            border.width: on ? 1 : 0
            border.color: Theme.outline
            activeFocusOnTab: on
            Accessible.role: Accessible.PageTab
            Accessible.name: modelData.label
            Accessible.selected: on
            Keys.onLeftPressed: event => { tb.go(index - 1); event.accepted = true }
            Keys.onRightPressed: event => { tb.go(index + 1); event.accepted = true }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Home) { tb.go(0); event.accepted = true }
                else if (event.key === Qt.Key_End) { tb.go(tb.tabs.length - 1); event.accepted = true }
            }
            MotionText {
                id: cap
                anchors.centerIn: parent
                color: tab.on ? Theme.fg : Theme.dim
                font.weight: tab.on ? Font.DemiBold : Font.Normal
                text: tab.modelData.label
            }
            // The open tab is underlined too, not only filled (never colour alone).
            Rectangle {
                visible: tab.on
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: cap.implicitWidth
                height: 2
                color: Theme.accent
            }
            MouseArea {
                anchors.fill: parent
                onClicked: tb.activated(tab.modelData.id)
            }
            FocusRing {
                anchors.fill: parent
                shown: tab.activeFocus
                corner: Theme.rSm
            }
        }
    }
}
