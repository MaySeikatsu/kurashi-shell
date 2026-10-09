import QtQuick
import "../core"
import "expanded"

// Quick settings (K24): the `quick` panel of runtime.ui, opened by the bar's quick button
// (`quick.toggle`). Bluetooth moved here from the island card; further sections go under it. The
// Stage makes this only while its card is up, so svc.bluetooth is watched only while it shows (Ma).
Column {
    id: quick
    width: parent.width
    spacing: Theme.pad

    Watch { doc: "svc.bluetooth" }
    readonly property var bluetooth: Store.docs["svc.bluetooth"] || ({})
    property string btErr: ""
    Refusal { id: refusal }

    // A bluetooth.* request. A refused one shows a translated line in the section.
    function btAct(action, args) {
        btErr = ""
        Store.act(action, args, function (done, err) {
            if (err) quick.btErr = refusal.text(err, "frontend.bt.failed")
        })
    }

    Text {
        width: quick.width
        color: Theme.fg
        font.pixelSize: Theme.fsTitle
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.heading")
    }
    // Visible only while the daemon serves svc.bluetooth (no BlueZ, nothing to show).
    BluetoothPanel {
        width: quick.width
        visible: quick.bluetooth.available === true
        doc: quick.bluetooth
        errText: quick.btErr
        onPowerRequested: on => quick.btAct("bluetooth.power", {on: on})
        onScanRequested: on => quick.btAct("bluetooth.scan", {on: on})
        onLinkRequested: (address, connect) =>
            quick.btAct(connect ? "bluetooth.connect" : "bluetooth.disconnect", {address: address})
    }
    Text {
        visible: quick.bluetooth.available !== true
        width: quick.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.empty")
    }
}
