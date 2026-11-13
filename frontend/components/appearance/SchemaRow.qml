import QtQuick
import "../../core"
import ".."
import "appearance.js" as A

// One schema row in an appearance pane (docs/ux/appearance-menu.md "Panes"), drawn by its control kind: a toggle as a
// switch row, a choice as a row of chips (a radio group: Left/Right move and preview), a range as a slider, a list of
// choices as toggle chips, a choice whose options the theme previews (palettes, styles, looks) as pictured tiles. A row
// the daemon holds inert stays, dimmed, with the reason under it (Shōjiki). Every change goes through the menu's
// preview session; Enter is the menu's (keep), so no control here takes it.
FocusScope {
    id: sr
    required property var row          // the schema.settings row
    required property var session      // PreviewSession
    property var previews: null        // the theme.previews document (tiles), when the pane watches it
    property var schema: null
    readonly property string key: row.key
    readonly property var prov: session.config.values ? session.config.values[key] : undefined
    readonly property var value: { var v = session.valueOf(key); return v !== undefined ? v : row.default }
    readonly property string control: row.control || ""
    readonly property var choices: row.choices || []
    readonly property string tileSource: control === "select" && previews && row.choices_from
        && Array.isArray(previews[row.choices_from]) ? row.choices_from : ""
    readonly property string why: inertWhy()
    readonly property bool inert: why !== ""
    readonly property bool pending: session.has(key)
    readonly property bool refusedHere: session.errorKey === key && session.error !== ""

    width: parent ? parent.width : 400
    implicitHeight: col.implicitHeight
    activeFocusOnTab: !inert
    Accessible.name: I18n.tr(row.label)
    Accessible.description: row.help ? I18n.tr(row.help) : ""

    // A style or a look is applied by its action (it resets the kind's keys, K53 — Settings' pickPack); "none" (your own)
    // and everything else is a value.
    readonly property var packActions: ({ styles: "theme.style.apply", looks: "theme.look.apply" })
    function set(v) {
        if (inert) return
        var action = packActions[row.choices_from || ""]
        if (action && v !== "none") session.showPack(key, action, v)
        else session.show(key, v)
    }
    // Why the row does nothing now: forced (accessibility, a capability), or another key it needs (the module menu's).
    function inertWhy() {
        var p = prov
        if (!p) return ""
        if (p.forced_by) {
            var f = A.rowOf(schema, p.forced_by)
            return I18n.tr("appearance-menu.inert.forced").replace("{key}", f ? I18n.tr(f.label) : p.forced_by)
        }
        if (p.reason === "settings.inert.requires" || p.inert_by) {
            var by = p.inert_by ? A.rowOf(schema, p.inert_by) : null
            if (!by) return I18n.tr("frontend.module.held")
            var text = I18n.tr(by.label), cs = row.couplings || []
            for (var i = 0; i < cs.length; i++) {
                if (cs[i].key !== p.inert_by || cs[i].kind !== "requires" || cs[i].op !== "eq") continue
                var ch = by.choices || []
                for (var j = 0; j < ch.length; j++) if (ch[j].value === cs[i].value) text += ": " + I18n.tr(ch[j].label)
            }
            return I18n.tr("frontend.module.needs").replace("{key}", text)
        }
        if (p.reason && !p.forced_by) return I18n.tr(p.reason)
        return ""
    }
    function choiceLabel(c) { return I18n.tr(c.label !== undefined ? c.label : String(c.value)) }
    function indexOfValue() {
        for (var i = 0; i < choices.length; i++) if (A.same(choices[i].value, value)) return i
        return -1
    }
    function moveChoice(d) {
        if (choices.length === 0) return
        var i = indexOfValue()
        var j = i < 0 ? 0 : Math.max(0, Math.min(choices.length - 1, i + d))
        if (j !== i) set(choices[j].value)
    }

    Keys.onLeftPressed: event => {
        if (control === "select" || tileSource !== "") moveChoice(-1)
        else if (control === "pick_list") chipsFocus = Math.max(0, chipsFocus - 1)
        else { event.accepted = false; return }
        event.accepted = true
    }
    Keys.onRightPressed: event => {
        if (control === "select" || tileSource !== "") moveChoice(1)
        else if (control === "pick_list") chipsFocus = Math.min(choices.length - 1, chipsFocus + 1)
        else { event.accepted = false; return }
        event.accepted = true
    }
    // A font is chosen in Settings (the installed fonts are a long list): Space opens it on the row's key.
    signal wantsSettings(string key)
    Keys.onSpacePressed: event => {
        if (control === "font") wantsSettings(key)
        else if (control === "toggle") set(!(value === true))
        else if (control === "pick_list") togglePick(chipsFocus)
        else { event.accepted = false; return }
        event.accepted = true
    }
    property int chipsFocus: 0
    function togglePick(i) {
        if (i < 0 || i >= choices.length) return
        var cur = Array.isArray(value) ? value.slice() : []
        var v = choices[i].value, at = cur.indexOf(v)
        if (at >= 0) cur.splice(at, 1); else cur.push(v)
        set(cur)
    }

    Column {
        id: col
        width: parent.width
        spacing: 6
        opacity: sr.inert ? 0.55 : 1

        // the head: the label (and, for a switch, the switch); the help under it for switches
        Item {
            width: parent.width
            height: Math.max(head.implicitHeight, sw.visible ? sw.height : 0)
            Column {
                id: head
                anchors.left: parent.left
                anchors.right: sw.visible ? sw.left : (valueText.visible ? valueText.left : parent.right)
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.weight: sr.control === "toggle" ? Theme.wRegular : Theme.wMedium
                    font.family: Theme.fam(text, Theme.families)
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    text: I18n.tr(sr.row.label) + (sr.pending ? "  •" : "")
                }
                Text {
                    width: parent.width
                    visible: sr.control === "toggle" && !!sr.row.help && text !== ""
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    text: sr.row.help ? I18n.tr(sr.row.help) : ""
                }
            }
            ToggleSwitch {
                id: sw
                visible: sr.control === "toggle"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                activeFocusOnTab: false
                checked: sr.value === true
                enabled: !sr.inert
                label: I18n.tr(sr.row.label)
                onToggled: on => sr.set(on)
            }
            // a slider's value, a font's family
            Text {
                id: valueText
                visible: sr.control === "slider" || sr.control === "font"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.features: { "tnum": 1 }
                font.family: sr.control === "font" && Array.isArray(sr.value) && sr.value.length > 0 ? String(sr.value[0])
                    : Theme.fam(text, Theme.families)
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                text: {
                    if (sr.control === "font") return Array.isArray(sr.value) ? sr.value.join(", ") : String(sr.value || "")
                    if (sr.control !== "slider") return ""
                    var v = Number(sr.value)
                    var st = Number(sr.row.step || 1)
                    var s = st < 1 ? v.toFixed(st < 0.1 ? 2 : 1) : String(Math.round(v))
                    return s + (sr.row.unit ? " " + sr.row.unit : "")
                }
            }
        }

        // a choice: chips (a radio group)
        Flow {
            id: chips
            visible: sr.control === "select" && sr.tileSource === ""
            width: parent.width
            spacing: Theme.xs
            Accessible.role: Accessible.Grouping
            Repeater {
                model: chips.visible ? sr.choices : []
                delegate: ChoiceChip {
                    required property var modelData
                    required property int index
                    label: sr.choiceLabel(modelData)
                    chosen: A.same(modelData.value, sr.value)
                    ringed: sr.activeFocus && chosen
                    enabled: !sr.inert
                    onPicked: { sr.forceActiveFocus(); sr.set(modelData.value) }
                }
            }
        }
        // a list of choices: toggle chips
        Flow {
            id: picks
            visible: sr.control === "pick_list"
            width: parent.width
            spacing: Theme.xs
            Repeater {
                model: picks.visible ? sr.choices : []
                delegate: ChoiceChip {
                    required property var modelData
                    required property int index
                    label: sr.choiceLabel(modelData)
                    chosen: Array.isArray(sr.value) && sr.value.indexOf(modelData.value) >= 0
                    check: true
                    ringed: sr.activeFocus && sr.chipsFocus === index
                    enabled: !sr.inert
                    onPicked: { sr.forceActiveFocus(); sr.chipsFocus = index; sr.togglePick(index) }
                }
            }
        }
        // a choice the theme previews: tiles in each option's own tokens
        Tiles {
            id: tiles
            visible: sr.tileSource !== ""
            dots: sr.row.choices_from === "palettes"
            width: parent.width
            cards: visible ? sr.previews[sr.tileSource] : []
            choices: sr.choices
            current: sr.value
            focused: sr.activeFocus
            onPicked: v => { sr.forceActiveFocus(); sr.set(v) }
        }
        // a range
        Slider {
            visible: sr.control === "slider"
            width: parent.width
            activeFocusOnTab: false
            focus: sr.control === "slider"
            readonly property real lo: Number(sr.row.min !== undefined ? sr.row.min : 0)
            readonly property real hi: Number(sr.row.max !== undefined ? sr.row.max : 1)
            value: hi > lo ? (Number(sr.value) - lo) / (hi - lo) : 0
            step: hi > lo && sr.row.step ? Number(sr.row.step) / (hi - lo) : 0.05
            unavailable: sr.inert
            a11y: I18n.tr(sr.row.label)
            onMoved: v => {
                var st = Number(sr.row.step || 0)
                var x = lo + v * (hi - lo)
                if (st > 0) x = Math.round(x / st) * st
                if (sr.row.type === "int") x = Math.round(x)
                sr.set(Math.max(lo, Math.min(hi, Number(x.toFixed(4)))))
            }
        }
        // why it does nothing now, or why the daemon refused the last change
        Text {
            width: parent.width
            visible: text !== ""
            wrapMode: Text.WordWrap
            color: sr.refusedHere ? Theme.error : Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            text: sr.refusedHere ? I18n.tr(sr.session.error) : sr.why
        }
    }
    MouseArea {
        anchors.fill: col
        visible: sr.control === "toggle"
        enabled: !sr.inert
        onClicked: { sr.forceActiveFocus(); sr.set(!(sr.value === true)) }
    }
    FocusRing {
        anchors.fill: parent
        anchors.margins: -4
        corner: Theme.rSm
        shown: sr.activeFocus && (sr.control === "toggle" || sr.control === "font")
    }
}
