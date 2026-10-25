import QtQuick
import "../../core"
import ".."

// The night light page (K47, docs/ux/power.md "Night light"): the switch (`nightlight.toggle {on}`, the tile's request), the
// warmth and the schedule. Everything shown is `svc.nightlight` — the value in effect — and a reason replaces the state
// when wlsunset is missing, the times are wrong or the sun schedule has no place. The warmth and the schedule are config
// writes (`night_light.temperature`, `night_light.schedule`); the slider sends one write when it rests (the timer runs only
// after a move, Ma), and the daemon's echo moves it.
Column {
    id: np
    width: parent.width
    spacing: Theme.gap
    property var nightReq: null
    signal backRequested()

    function focusFirst() { header.forceActiveFocus() }

    readonly property var d: Store.docs["svc.nightlight"] || ({})
    readonly property bool known: Store.docs["svc.nightlight"] !== undefined
    readonly property bool enabled: d.enabled === true
    readonly property int temperature: Number(d.temperature || 4000)
    readonly property string schedule: String(d.schedule || "manual")
    // I130: "22:00–06:30", the night `svc.nightlight` has in effect ("" while it has none).
    readonly property string span: d.start && d.end ? String(d.start) + "–" + String(d.end) : ""
    readonly property string reason: d.available === false && d.reason ? I18n.tr(String(d.reason)) : ""
    // The warmth slider runs warm to the right: 6500 K (none) at 0, 1500 K at 1.
    readonly property real warmth: Math.max(0, Math.min(1, (6500 - temperature) / 5000))
    property int pendingK: 0

    // A config write (Store.apply, row 134): the document shows what is in effect; a refusal is said in the state line.
    property string refusal: ""
    function apply(key, value) {
        Store.apply([{set: key, value: value}], function (errors) {
            np.refusal = errors && errors.length ? I18n.tr(String(errors[0].code || "")) : ""
        })
    }
    function stateText() {
        if (np.refusal !== "") return np.refusal
        if (!np.enabled) return I18n.tr("island.quick.off")
        if (np.reason !== "") return np.reason
        if (np.schedule === "always") return I18n.tr("power.night.state.always")
        var t = String(np.d.next_change || "")
        if (np.d.active === true) return t !== "" ? I18n.tr("power.night.state.on_until").replace("{t}", t) : I18n.tr("island.quick.on")
        return t !== "" ? I18n.tr("power.night.state.off_until").replace("{t}", t) : I18n.tr("island.quick.off")
    }

    Timer {
        id: settle
        interval: 400
        onTriggered: if (np.pendingK > 0) { np.apply("night_light.temperature", np.pendingK); np.pendingK = 0 }
    }

    PageHeader {
        id: header
        title: I18n.tr("power.night.title")
        backName: I18n.tr("island.quick.back")
        onBack: np.backRequested()
    }
    Row {
        width: np.width
        spacing: Theme.gap
        Column {
            width: parent.width - nightSwitch.width - Theme.gap
            anchors.verticalCenter: nightSwitch.verticalCenter
            Text {
                width: parent.width
                elide: Text.ElideRight
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("power.night.title")
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: np.enabled && np.reason !== "" ? Theme.error : Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: np.stateText()
            }
        }
        ToggleSwitch {
            id: nightSwitch
            checked: np.enabled
            enabled: np.known && !(np.nightReq !== null && np.nightReq.pending)
            label: I18n.tr("power.night.title")
            onToggled: on => { if (np.nightReq !== null) np.nightReq.begin(on) }
        }
    }
    StateLine {
        width: np.width
        req: np.nightReq
        pendingText: I18n.tr("island.quick.changing")
    }
    Text {
        width: np.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("power.night.warmth")
    }
    LevelRow {
        width: np.width
        glyph: "◐"
        icon: "thermostat"
        value: np.warmth
        readout: (np.pendingK > 0 ? np.pendingK : np.temperature) + " K"
        unavailable: !np.known
        a11y: I18n.tr("power.night.warmth")
        // 100 K steps, as the schema's step.
        onMoved: v => { np.pendingK = Math.round((6500 - v * 5000) / 100) * 100; settle.restart() }
    }
    Text {
        width: np.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("power.night.schedule")
    }
    ChoiceRow {
        width: np.width
        radio: true
        checked: np.schedule === "manual"
        inert: checked
        title: I18n.tr("power.night.schedule.manual")
        // I130: the night in effect, when the daemon knows it (the times by hand).
        sub: (checked && np.span !== "" ? np.span + " · " : "") + I18n.tr("power.night.schedule.manual_sub")
        onActivated: np.apply("night_light.schedule", "manual")
    }
    ChoiceRow {
        width: np.width
        radio: true
        checked: np.schedule === "sun"
        inert: checked
        title: I18n.tr("power.night.schedule.sun")
        // I130: today's sunset to sunrise at the place.
        sub: (checked && np.span !== "" ? np.span + " · " : "") + I18n.tr("power.night.schedule.sun_sub")
        onActivated: np.apply("night_light.schedule", "sun")
    }
    ChoiceRow {
        width: np.width
        radio: true
        checked: np.schedule === "always"
        inert: checked
        title: I18n.tr("power.night.schedule.always")
        onActivated: np.apply("night_light.schedule", "always")
    }
}
