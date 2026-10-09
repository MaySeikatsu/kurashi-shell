import QtQuick
import "../../core"

// Power in quick settings (K24, W12): the battery's percent and state with the time left or to full, or
// "On AC power" without a battery. Without UPower (`available:false`) one dim line says why. Watches
// svc.power only while the card is up (Ma).
Column {
    id: pw
    width: parent.width
    spacing: Theme.xs

    Watch { doc: "svc.power" }
    readonly property var d: Store.docs["svc.power"] || ({})
    readonly property bool avail: d.available === true
    readonly property bool battery: d.present === true

    // UPower's state names; an absent or unknown state adds no word.
    function stateWord() {
        switch (d.state) {
        case "charging": return I18n.tr("island.quick.power.charging")
        case "discharging": return I18n.tr("island.quick.power.discharging")
        case "empty": return I18n.tr("island.quick.power.empty")
        case "full": return I18n.tr("island.quick.power.full")
        case "pending_charge": return I18n.tr("island.quick.power.pending_charge")
        case "pending_discharge": return I18n.tr("island.quick.power.pending_discharge")
        default: return ""
        }
    }
    // Whole minutes, at least one: "1 h 20 min", "35 min".
    function duration(s) {
        var m = Math.max(1, Math.round(s / 60))
        if (m >= 60)
            return I18n.tr("island.quick.power.hm").replace("{h}", String(Math.floor(m / 60))).replace("{m}", String(m % 60))
        return I18n.tr("island.quick.power.m").replace("{m}", String(m))
    }
    // "78 % · Charging": the percent only when the daemon has one.
    function headline() {
        var parts = []
        if (d.percent !== undefined) parts.push(Math.round(d.percent) + " %")
        var w = stateWord()
        if (w !== "") parts.push(w)
        return parts.join(" · ")
    }
    // The time left (discharging) or to full (charging), when UPower gives one.
    function timeLine() {
        if (d.time_to_empty_s !== undefined)
            return I18n.tr("island.quick.power.to_empty").replace("{t}", duration(d.time_to_empty_s))
        if (d.time_to_full_s !== undefined)
            return I18n.tr("island.quick.power.to_full").replace("{t}", duration(d.time_to_full_s))
        return ""
    }

    Text {
        visible: !pw.avail
        width: pw.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.power.unavailable")
    }
    Row {
        visible: pw.avail
        width: pw.width
        spacing: Theme.gap
        Text {
            width: pw.width - value.width - Theme.gap
            elide: Text.ElideRight
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("island.quick.power.heading")
        }
        Text {
            id: value
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: pw.battery ? pw.headline() : I18n.tr("island.quick.power.ac")
        }
    }
    Text {
        visible: pw.avail && pw.battery && pw.timeLine() !== ""
        width: pw.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: pw.timeLine()
    }
}
