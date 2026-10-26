import QtQuick
import "../../core"
import ".."

// Module `workspaces`: this output's workspaces (svc.workspaces `outputs`, or the "*" list for every output). In a row:
// flat chrome a dot each, the focused one a wider accent bar; chromes with groups a small numbered key — focused lit in
// the accent, occupied on the container (an outlined box under line chrome), empty on the ring (keycap) or bare — that
// sinks, shrinks or flashes while pressed. In a column: dots, the focused one taller. A click focuses the workspace (niri's
// own action through the daemon). The chips are the drop targets of the window list (the link's `chips`).
ModuleBase {
    id: m
    Watch { doc: "svc.workspaces"; active: m.live }
    readonly property var doc: Store.docs["svc.workspaces"] || ({})
    readonly property var pills: {
        var o = doc.outputs || {}
        return o[m.output] || o["*"] || []
    }
    readonly property int dragWs: m.link ? m.link.dragWs : -1
    implicitWidth: vertical ? col.implicitWidth : row.implicitWidth
    implicitHeight: vertical ? col.implicitHeight : row.implicitHeight
    width: implicitWidth
    height: implicitHeight

    function publish(rep) {
        if (!m.link) return
        var a = []
        for (var i = 0; i < rep.count; i++) a.push(rep.itemAt(i))
        m.link.chips = a
    }
    function geo() { return [["workspaces", m]] }

    Component {
        id: dotPill
        Rectangle {
            required property var modelData
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            height: modelData.focused ? 10 : 8
            width: modelData.focused ? 24 : 8
            radius: height / 2
            color: modelData.focused ? Theme.accent : (modelData.occupied ? Theme.fg : "transparent")
            border.width: (!modelData.focused && !modelData.occupied) ? 1 : 0
            border.color: Theme.dim
            Behavior on width {
                enabled: m.live
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot }
            }
            // A window dragged over this workspace (W36): a ring round the dot.
            Rectangle {
                visible: m.dragWs === modelData.id
                anchors.centerIn: parent
                width: parent.width + 8
                height: parent.height + 8
                radius: height / 2
                color: "transparent"
                border.width: 2
                border.color: Theme.accent
            }
        }
    }
    Component {
        id: keyPill
        Block {
            id: kp
            required property var modelData
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            anchors.verticalCenterOffset: Theme.shadowDy / 2
            width: modelData.focused ? 34 : 22
            height: 20 + Theme.shadowDy
            radius: Theme.rFull
            ringScale: 0
            softScale: 0
            pressed: wsTap.pressed
            fill: modelData.focused ? Theme.accent
                : (modelData.occupied ? (Theme.lifted ? Theme.containerHigh : "transparent")
                    : (Theme.ringW > 0 ? Theme.ring : "transparent"))
            opacity: modelData.focused || modelData.occupied ? 1 : 0.7
            Behavior on width {
                enabled: m.live && Theme.springOn
                NumberAnimation { duration: Theme.stdMs + 80; easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot }
            }
            Text {
                anchors.centerIn: parent
                color: kp.modelData.focused ? Theme.fgOnAccent : (kp.modelData.occupied ? Theme.fg : Theme.dim)
                font.pixelSize: Theme.fsCaption
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                text: kp.modelData.idx ?? ""
            }
            TapHandler { id: wsTap; onTapped: Store.act("workspace.focus", {id: kp.modelData.id}) }
            // A window dragged over this workspace (W36): a ring round the key.
            Rectangle {
                visible: m.dragWs === kp.modelData.id
                anchors.fill: parent
                anchors.margins: -3
                radius: height / 2
                color: "transparent"
                border.width: 2
                border.color: Theme.accent
            }
        }
    }
    Component {
        id: columnPill
        Item {
            required property var modelData
            width: m.thickness
            height: modelData.focused ? 24 : 8
            Rectangle {
                anchors.centerIn: parent
                width: modelData.focused ? 10 : 8
                height: parent.height
                radius: width / 2
                color: modelData.focused ? Theme.accent : (modelData.occupied ? Theme.fg : "transparent")
                border.width: (!modelData.focused && !modelData.occupied) ? 1 : 0
                border.color: Theme.dim
            }
            // A window dragged over this workspace (W36): a ring round the dot.
            Rectangle {
                visible: m.dragWs === modelData.id
                anchors.centerIn: parent
                width: 18
                height: parent.height + 8
                radius: width / 2
                color: "transparent"
                border.width: 2
                border.color: Theme.accent
            }
        }
    }

    Row {
        id: row
        visible: !m.vertical
        spacing: Theme.groups ? Theme.xs + 1 : Theme.gap
        Repeater {
            id: repH
            model: m.vertical ? [] : m.pills
            delegate: Theme.groups ? keyPill : dotPill
            onItemAdded: Qt.callLater(m.publish, repH)
            onItemRemoved: Qt.callLater(m.publish, repH)
        }
    }
    Column {
        id: col
        visible: m.vertical
        spacing: Theme.gap
        Repeater {
            id: repV
            model: m.vertical ? m.pills : []
            delegate: columnPill
            onItemAdded: Qt.callLater(m.publish, repV)
            onItemRemoved: Qt.callLater(m.publish, repV)
        }
    }
}
