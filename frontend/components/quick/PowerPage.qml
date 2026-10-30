import QtQuick
import "../../core"
import ".."

// The power page (docs/ux/quick-settings.md, Design 2): the battery's percent, its state and the time left or to full, or
// "On AC power" without a battery; then the power profiles the daemon offers, the active one marked. Without UPower one
// dim line says why; without power-profiles-daemon the profile list says why it is absent (`profile_reason`). Choosing a
// profile is one request (`profReq`, from QuickPanel); the mark follows the daemon's document only.
Column {
    id: pw
    width: parent.width
    spacing: Theme.gap
    property var profReq: null
    signal backRequested()

    function focusFirst() { header.forceActiveFocus() }

    readonly property var d: Store.docs["svc.power"] || ({})
    readonly property bool avail: d.available === true
    readonly property bool battery: d.present === true
    readonly property var profiles: avail && d.profiles ? d.profiles : []

    ListModel { id: profRows }
    function syncProfiles() {
        var list = profiles
        for (var i = 0; i < list.length; i++) {
            var r = {name: String(list[i])}
            if (i < profRows.count) profRows.set(i, r)
            else profRows.append(r)
        }
        while (profRows.count > list.length) profRows.remove(profRows.count - 1)
    }
    onProfilesChanged: syncProfiles()
    Component.onCompleted: syncProfiles()

    // The profile's name in copy; a name the copy lacks is shown as the daemon gives it.
    function profLabel(name) {
        var k = "island.quick.power.profile." + name
        var t = I18n.tr(k)
        return t === k ? name : t
    }
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
    // The time left (discharging) or to full (charging), when UPower gives one.
    function timeLine() {
        if (d.time_to_empty_s !== undefined)
            return I18n.tr("island.quick.power.to_empty").replace("{t}", duration(d.time_to_empty_s))
        if (d.time_to_full_s !== undefined)
            return I18n.tr("island.quick.power.to_full").replace("{t}", duration(d.time_to_full_s))
        return ""
    }
    function stateLine() {
        var parts = [stateWord(), timeLine()].filter(function (p) { return p !== "" })
        return parts.join(" · ")
    }

    PageHeader {
        id: header
        title: I18n.tr("island.quick.tile.power")
        backName: I18n.tr("island.quick.back")
        onBack: pw.backRequested()
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: !pw.avail
        width: pw.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.power.unavailable")
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: pw.avail && pw.battery && pw.d.percent !== undefined
        width: pw.width
        color: Theme.fg
        font.pixelSize: Theme.fsTitle + 4
        font.family: Theme.fam(text, Theme.families)
        text: Math.round(Number(pw.d.percent || 0)) + " %"
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: pw.avail && pw.battery && pw.stateLine() !== ""
        width: pw.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: pw.stateLine()
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: pw.avail && !pw.battery
        width: pw.width
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.power.ac")
    }

    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: pw.avail && pw.profiles.length > 0
        width: pw.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.power.profile")
    }
    Repeater {
        model: profRows
        delegate: ChoiceRow {
            required property string name
            width: pw.width
            title: pw.profLabel(name)
            radio: true
            checked: pw.d.profile === name
            pending: pw.profReq !== null && pw.profReq.want === name
            pendingText: I18n.tr("island.quick.changing")
            onActivated: { if (pw.d.profile !== name && pw.profReq !== null) pw.profReq.begin(name) }
        }
    }
    StateLine {
        width: pw.width
        req: pw.profReq
        pendingText: I18n.tr("island.quick.changing")
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: pw.avail && pw.profiles.length === 0 && pw.d.profile_reason !== undefined
        width: pw.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr(String(pw.d.profile_reason || ""))
    }
}
