import QtQuick
import "../core"

// Bluetooth in the island panel: the adapter's power, its scan, and the devices svc.bluetooth lists.
// A pure view: every control signals one request and the Stage sends the bluetooth.* action. The
// nearby (unpaired) devices show only while a scan runs. Errors come in as a translated `errText`.
Column {
    id: bt
    property var doc: ({})            // svc.bluetooth as the daemon serves it
    property string errText: ""       // translated line for the last refused request, or ""
    // false on a page whose own header names the panel and carries the power switch: no second title row.
    property bool titled: true
    readonly property bool powered: doc.powered === true
    readonly property bool discovering: doc.discovering === true
    readonly property var paired: (doc.devices || []).filter(function (d) { return d.paired === true })
    readonly property var nearby: (doc.devices || []).filter(function (d) { return d.paired !== true })

    signal powerRequested(bool on)
    signal scanRequested(bool on)
    signal linkRequested(string address, bool connect)

    // The device rows are ListModels updated in place. Every patch of svc.bluetooth brings new arrays, and a
    // Repeater over them rebuilds each row, so a focused Connect or Disconnect button lost its focus after its
    // own action. Rows keep their delegates by position, as the audio rows do, and carry plain values only.
    ListModel { id: pairedRows }
    ListModel { id: nearbyRows }
    function rowOf(d) {
        var parts = [d.connected === true ? I18n.tr("frontend.bt.connected")
            : (d.paired === true ? I18n.tr("frontend.bt.paired") : I18n.tr("frontend.bt.new"))]
        if (d.battery !== undefined) parts.push(I18n.tr("frontend.bt.battery") + " " + d.battery + "%")
        return {address: String(d.address || ""), title: String(d.name || d.address || ""),
                stateLine: parts.join(" · "), connected: d.connected === true}
    }
    function syncRows(model, list) {
        for (var i = 0; i < list.length; i++) {
            if (i < model.count) model.set(i, rowOf(list[i]))
            else model.append(rowOf(list[i]))
        }
        while (model.count > list.length) model.remove(model.count - 1)
    }
    // Read from `doc` itself: on a change of `doc`, the derived bindings (powered, paired) may not have updated yet.
    function syncAll() {
        var devices = doc.devices || []
        var on = doc.powered === true
        syncRows(pairedRows, on ? devices.filter(function (d) { return d.paired === true }) : [])
        syncRows(nearbyRows, on && doc.discovering === true
                 ? devices.filter(function (d) { return d.paired !== true }) : [])
    }
    onDocChanged: syncAll()
    Component.onCompleted: syncAll()

    spacing: Theme.gap

    Row {
        visible: bt.titled
        width: bt.width
        spacing: Theme.gap
        Text {
            width: bt.width - power.width - Theme.gap
            anchors.verticalCenter: power.verticalCenter
            elide: Text.ElideRight
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("frontend.bt.title")
        }
        ToggleSwitch {
            id: power
            checked: bt.powered
            label: I18n.tr("frontend.bt.title")
            onToggled: on => bt.powerRequested(on)
        }
    }

    Text {
        visible: !bt.powered
        width: bt.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("frontend.bt.off_hint")
    }

    Button {
        visible: bt.powered
        label: bt.discovering ? I18n.tr("frontend.bt.scan_stop") : I18n.tr("frontend.bt.scan")
        onClicked: bt.scanRequested(!bt.discovering)
    }

    Text {
        visible: bt.powered
        width: bt.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("frontend.bt.devices")
    }
    Repeater {
        model: pairedRows
        delegate: deviceRow
    }
    Text {
        visible: bt.powered && bt.paired.length === 0
        width: bt.width
        color: Theme.dim
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("frontend.bt.none")
    }

    Text {
        visible: bt.powered && bt.discovering
        width: bt.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("frontend.bt.nearby")
    }
    Repeater {
        model: nearbyRows
        delegate: deviceRow
    }

    Text {
        visible: bt.errText !== ""
        width: bt.width
        wrapMode: Text.WordWrap
        color: Theme.error
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: bt.errText
    }

    // One device: name, a state line (connected, paired or not, battery), and the link button.
    Component {
        id: deviceRow
        Item {
            id: dev
            required property string address
            required property string title
            required property string stateLine
            required property bool connected

            width: bt.width
            height: Math.max(Theme.controlH, labels.implicitHeight)

            Column {
                id: labels
                anchors.left: parent.left
                anchors.right: link.left
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: dev.title
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: dev.stateLine
                }
            }
            Button {
                id: link
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: dev.connected ? I18n.tr("frontend.bt.disconnect") : I18n.tr("frontend.bt.connect")
                onClicked: bt.linkRequested(dev.address, !dev.connected)
            }
        }
    }
}
