import QtQuick
import "../../core"
import "../expanded"
import ".."

// Wi-Fi and the primary connection in quick settings (K24, W12). The switch sets the Wi-Fi radio
// (`network.wifi`), and its state follows NetworkManager, never the click: the daemon's document is the
// only truth. While svc.network says `unavailable` (NetworkManager not on the bus) one dim line says why
// and no control is drawn. Watches svc.network only while the card is up (Ma).
Column {
    id: net
    width: parent.width
    spacing: Theme.gap

    Watch { doc: "svc.network" }
    readonly property var d: Store.docs["svc.network"] || ({})
    readonly property bool avail: typeof d.state === "string" && d.state !== "unavailable"
    readonly property bool wifiOn: d.wifi_enabled === true
    readonly property var primary: d.primary || null
    property string errText: ""
    Refusal { id: refusal }

    // NetworkManager's state and kind names; anything else reads as "unknown" or "other".
    readonly property var stateNames: ["connected", "local", "site", "connecting", "disconnecting", "disconnected", "asleep"]
    readonly property var kindNames: ["wifi", "ethernet", "vpn", "bluetooth"]

    function setWifi(on) {
        net.errText = ""
        Store.act("network.wifi", {on: on}, function (done, err) {
            if (err) net.errText = refusal.text(err, "island.quick.network.failed")
        })
    }
    // "Connected · Home-5G (Wi-Fi) · Signal 72 %": the state, then the primary connection and its kind.
    function summary() {
        var st = stateNames.indexOf(d.state) >= 0 ? d.state : "unknown"
        var parts = [I18n.tr("island.quick.network.state." + st)]
        if (primary) {
            var kind = kindNames.indexOf(primary.kind) >= 0 ? primary.kind : "other"
            var label = I18n.tr("island.quick.network.kind." + kind)
            var name = String(primary.name || "")
            parts.push(name !== "" ? name + " (" + label + ")" : label)
            if (kind === "wifi" && primary.strength !== undefined)
                parts.push(I18n.tr("island.quick.network.signal").replace("{n}", String(Math.round(primary.strength))))
        }
        return parts.join(" · ")
    }
    // Lit bars of the Wi-Fi strength: one per 25 %, and at least one for any signal.
    function lit() {
        if (!primary || primary.kind !== "wifi" || primary.strength === undefined) return 0
        return Math.min(4, Math.ceil(primary.strength / 25))
    }

    // Not available: the one dim line that says why, and no control.
    Text {
        visible: !net.avail
        width: net.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.network.unavailable")
    }
    Column {
        visible: net.avail
        width: net.width
        spacing: Theme.gap

        Row {
            width: parent.width
            spacing: Theme.gap
            Text {
                width: parent.width - wifiSwitch.width - Theme.gap
                anchors.verticalCenter: wifiSwitch.verticalCenter
                elide: Text.ElideRight
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("island.quick.network.heading")
            }
            ToggleSwitch {
                id: wifiSwitch
                checked: net.wifiOn
                label: I18n.tr("island.quick.network.heading")
                onToggled: on => net.setWifi(on)
            }
        }
        Row {
            width: parent.width
            spacing: Theme.gap
            Text {
                width: parent.width - (bars.visible ? bars.width + Theme.gap : 0)
                anchors.verticalCenter: bars.verticalCenter
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: net.summary()
            }
            // Signal bars (Wi-Fi only): four steps, lit ones in the foreground colour, the rest outline.
            Row {
                id: bars
                spacing: 2
                height: 13
                visible: net.primary !== null && net.primary.kind === "wifi" && net.primary.strength !== undefined
                Repeater {
                    model: 4
                    Item {
                        required property int index
                        width: 3
                        height: bars.height
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 4 + parent.index * 3
                            radius: 1
                            color: parent.index < net.lit() ? Theme.fg : Theme.outline
                        }
                    }
                }
            }
        }
        Text {
            visible: net.errText !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.error
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: net.errText
        }
    }
}
