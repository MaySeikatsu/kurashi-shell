import QtQuick
import "../../core"
import "../expanded"
import ".."

// The Bluetooth page (docs/ux/quick-settings.md, Design 2): the existing BluetoothPanel, which has the adapter's switch,
// its scan and the devices with their battery. Every control sends one bluetooth.* request; a refused one shows its line
// here. Without an adapter, or with BlueZ gone, one dim line says why.
Column {
    id: bt
    width: parent.width
    spacing: Theme.gap
    signal backRequested()

    function focusFirst() { header.forceActiveFocus() }

    readonly property var d: Store.docs["svc.bluetooth"] || ({})
    readonly property bool avail: d.available === true
    property string errText: ""
    Refusal { id: refusal }

    function act(action, args) {
        bt.errText = ""
        Store.act(action, args, function (done, err) {
            if (err) bt.errText = refusal.text(err, "island.quick.bluetooth.failed")
        })
    }

    PageHeader {
        id: header
        title: I18n.tr("island.quick.tile.bluetooth")
        backName: I18n.tr("island.quick.back")
        onBack: bt.backRequested()
    }
    BluetoothPanel {
        visible: bt.avail
        width: bt.width
        doc: bt.d
        errText: bt.errText
        onPowerRequested: on => bt.act("bluetooth.power", {on: on})
        onScanRequested: on => bt.act("bluetooth.scan", {on: on})
        onLinkRequested: (address, connect) =>
            bt.act(connect ? "bluetooth.connect" : "bluetooth.disconnect", {address: address})
    }
    Text {
        visible: !bt.avail
        width: bt.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.bluetooth.unavailable")
    }
}
