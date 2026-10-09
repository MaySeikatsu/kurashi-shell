import QtQuick
import "../../core"
import "../expanded"
import ".."

// Bluetooth in quick settings (K24): BluetoothPanel over svc.bluetooth, moved here from QuickPanel with
// the other sections. Without an adapter, or with BlueZ gone, one dim line says why. Watches
// svc.bluetooth only while the card is up (Ma).
Column {
    id: bt
    width: parent.width
    spacing: Theme.gap

    Watch { doc: "svc.bluetooth" }
    readonly property var d: Store.docs["svc.bluetooth"] || ({})
    readonly property bool avail: d.available === true
    property string errText: ""
    Refusal { id: refusal }

    // A bluetooth.* request. A refused one shows a translated line in the section.
    function act(action, args) {
        bt.errText = ""
        Store.act(action, args, function (done, err) {
            if (err) bt.errText = refusal.text(err, "frontend.bt.failed")
        })
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
