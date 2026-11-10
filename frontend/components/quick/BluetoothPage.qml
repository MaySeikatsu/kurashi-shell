import QtQuick
import "../../core"
import "../expanded"
import ".."

// The Bluetooth page (docs/ux/quick-settings.md, Design 2): the header with the adapter's switch, then the existing
// BluetoothPanel (its scan and the devices with their battery, without its own title row). Every control sends one bluetooth.* request; a refused one shows its line
// here. Without an adapter, or with BlueZ gone, one dim line says why.
Column {
    id: bt
    // W71: the module ids whose options the page lists (the module that opened it; none from the tiles).
    property var optionIds: []
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

    // The header names the page and carries the adapter's switch; the panel's own title row is off here.
    Row {
        width: bt.width
        spacing: Theme.gap
        PageHeader {
            id: header
            title: I18n.tr("island.quick.tile.bluetooth")
            backName: I18n.tr("island.quick.back")
            onBack: bt.backRequested()
        }
        Item {
            width: bt.width - header.width - sw.width - 2 * Theme.gap
            height: sw.height
        }
        ToggleSwitch {
            id: sw
            // (B73: an adapter that is not there is not on — the switch draws off while it is inert, Shōjiki)
            checked: bt.avail && bt.d.powered === true
            enabled: bt.avail
            label: I18n.tr("frontend.bt.title")
            onToggled: on => bt.act("bluetooth.power", {on: on})
        }
    }
    BluetoothPanel {
        visible: bt.avail
        titled: false
        width: bt.width
        doc: bt.d
        errText: bt.errText
        onPowerRequested: on => bt.act("bluetooth.power", {on: on})
        onScanRequested: on => bt.act("bluetooth.scan", {on: on})
        onLinkRequested: (address, connect) =>
            bt.act(connect ? "bluetooth.connect" : "bluetooth.disconnect", {address: address})
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        visible: !bt.avail
        width: bt.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.bluetooth.unavailable")
    }
    // W71 (I475 3): the options of the module that opened the page (its click among them), as its menu lists them;
    // what the page draws itself is left out.
    ModuleOptions {
        width: bt.width
        mids: bt.optionIds
        skip: []
    }
}
