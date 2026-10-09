import QtQuick
import "../core"

// Bluetooth in the island panel: the adapter's power, its scan, and the devices svc.bluetooth lists.
// A pure view: every control signals one request and the Stage sends the bluetooth.* action. The
// nearby (unpaired) devices show only while a scan runs. Errors come in as a translated `errText`.
Column {
    id: bt
    property var doc: ({})            // svc.bluetooth as the daemon serves it
    property string errText: ""       // translated line for the last refused request, or ""
    readonly property bool powered: doc.powered === true
    readonly property bool discovering: doc.discovering === true
    readonly property var paired: (doc.devices || []).filter(function (d) { return d.paired === true })
    readonly property var nearby: (doc.devices || []).filter(function (d) { return d.paired !== true })

    signal powerRequested(bool on)
    signal scanRequested(bool on)
    signal linkRequested(string address, bool connect)

    spacing: Theme.gap

    Row {
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
        BluetoothSwitch {
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
        model: bt.powered ? bt.paired : []
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
        model: bt.powered && bt.discovering ? bt.nearby : []
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
            required property var modelData
            readonly property bool connected: modelData.connected === true
            readonly property string stateLine: [
                connected ? I18n.tr("frontend.bt.connected")
                    : (modelData.paired === true ? I18n.tr("frontend.bt.paired") : I18n.tr("frontend.bt.new")),
                modelData.battery !== undefined ? I18n.tr("frontend.bt.battery") + " " + modelData.battery + "%" : ""
            ].filter(function (s) { return s !== "" }).join(" · ")

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
                    text: dev.modelData.name || dev.modelData.address
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
                onClicked: bt.linkRequested(dev.modelData.address, !dev.connected)
            }
        }
    }
}
