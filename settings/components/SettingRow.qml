import QtQuick
import "../core"
import "../components"

// One schema row (DESIGN-SYSTEM §7; UX brief, settings "Design"). The label and its help sit on the left. The control
// sits on the right, and under it the provenance chip with Reset (or, while a preview is open, Keep and Put back). Then
// the reasons the row is inert, each with a link to the setting that controls it, and any refusal. Generated from one
// schema row: nothing here knows a particular setting (rule 3), except the preview policy in Changes.
Item {
    id: r
    // The key of the schema row this one shows. The row itself is read live from the schema (Store.rowOf), so a value
    // change the daemon publishes updates the row in place, without a rebuild that would lose the focus (SettingsPages).
    property string rowKey: ""
    readonly property var row: { Store.schema; var h = Store.rowOf(r.rowKey); return h ? h.row : ({}) }
    // The selected output (per_output rows); "" = all outputs.
    property string output: ""
    // A link to the setting that controls this row (a reason's "open").
    signal openKey(string key)
    // The hairline under the row; a section card leaves it off its last row.
    property bool divider: true

    // The offers of a choice control, replaced only when their content changes: the daemon re-publishes the schema after
    // a change, and an open dropdown must keep its highlight when the offers it shows are the same.
    readonly property var liveOffers: r.row.choices ?? []
    property var offers: []
    property string offersSig: ""
    function refreshOffers(): void {
        const sig = JSON.stringify(r.liveOffers)
        if (sig !== r.offersSig) {
            r.offersSig = sig
            r.offers = r.liveOffers
        }
    }
    onLiveOffersChanged: refreshOffers()
    Component.onCompleted: {
        refreshOffers()
        if (r.wantsPreviews) Store.watch("theme.previews")
    }
    // The block layout of the Appearance page (W29): the row's name is the card's title, so the left column gives way to
    // one line saying what the setting is (its kind's `settings.appearance.<source>.what`), and the control takes the
    // whole width under it.
    property bool stacked: false

    readonly property string out: row.per_output ? output : ""
    readonly property var prov: Store.prov(row.key, out)
    readonly property bool previewing: Changes.activeFor(row.key, out)
    readonly property bool previewable: Changes.previewable(row.key)
    // What the control shows: the value a preview moved to while one is open, else the daemon's.
    readonly property var value: previewing ? Changes.session.shown : (prov === undefined ? row.default : prov.value)
    readonly property var reasons: { Store.config; return Store.inertReasons(row, out) }
    // A pending restart, an offer that is gone (I9) and a mod that is off (K22) are not inertness: the value can still be
    // changed, and reset, meanwhile.
    readonly property bool inert: reasons.some(function (x) {
        return x.kind !== "pending" && x.kind !== "unavailable" && x.kind !== "mod_off"
    })
    readonly property bool editable: !inert && Store.live
    // A select with offers from the daemon (or more than four fixed ones) is a dropdown; two fixed ones are a switch;
    // three to four stay pills (BACKLOG I9, UX brief "Controls").
    // A row whose offers are appearance packs (K53: offers from `styles`, `looks` or `palettes`, the keys of
    // `theme.previews`). The previews are watched only while a row that shows them exists (Ma).
    readonly property bool wantsPreviews: Store.isPackRow(row)
    // Picking a style or a look is its action (it resets that kind's settings), not a value: no preview on arrows.
    readonly property bool packAction: Store.packActions[row.choices_from] !== undefined
    Component.onDestruction: if (r.wantsPreviews) Store.unwatch("theme.previews")
    // Offers with a look of their own (K45, I104, K53) are preview cards: name -> {tokens, frame?}, from `theme.previews`.
    readonly property var looks: {
        var pv = Store.docs["theme.previews"]
        var m = {}, list = (pv && r.wantsPreviews && pv[row.choices_from]) || []
        for (var i = 0; i < list.length; i++) m[list[i].name] = list[i]
        return m
    }
    readonly property bool cards: row.control === "select" && (row.choices ?? []).filter(function (c) {
        return r.looks[c.value] !== undefined
    }).length >= 2
    readonly property bool dropdown: !cards && row.control === "select" && !!(row.choices_from || (row.choices ?? []).length > 4)
    readonly property bool switchChoice: row.control === "select" && !dropdown && (row.choices ?? []).length === 2
    readonly property string error: Store.rowErrors[row.key] || ""
    readonly property bool canReset: prov !== undefined && prov.source && prov.source.kind === "user" && !inert
    readonly property real labelW: Math.min(300, Math.max(180, width * 0.36))
    readonly property bool wide: row.control === "slider" || row.control === "pick_list" || row.control === "list"
        || row.control === "font" || row.control === "action_binding" || row.control === "text" || row.control === "number"
        || row.control === "color" || row.control === "select" && !switchChoice || row.control === "records"
    // A records row (K38) shows a refusal of one of its fields at that field; the row's own line keeps the rest.
    readonly property bool fieldRefusal: row.control === "records" && Store.fieldErrors[row.key] !== undefined

    implicitHeight: body.implicitHeight + Theme.gap * 2
    implicitWidth: 600

    // A value the control picked (Enter, a click, Keep): the open preview is kept, or the value is one change.
    function setValue(v) {
        if (packAction) { if (JSON.stringify(v) !== JSON.stringify(value) || r.overridden) Store.pickPack(row, v); return }
        if (previewing) {
            if (JSON.stringify(v) !== JSON.stringify(value)) Changes.show(row.key, out, v, prov)
            Changes.keep()
            return
        }
        if (JSON.stringify(v) === JSON.stringify(value)) return
        if (previewable) { Changes.show(row.key, out, v, prov); Changes.keep(); return }
        Store.setValue(row.key, v, out)
    }
    // A move by key (arrows, type-ahead): a previewable row shows it; any other row takes it as a change, as radio
    // groups do.
    function moveTo(v) {
        if (JSON.stringify(v) === JSON.stringify(value)) return
        if (previewable) Changes.show(row.key, out, v, prov)
        else Store.setValue(row.key, v, out)
    }
    // A pack picked again while settings differ from it applies it again (the reset to the style; W29).
    readonly property bool overridden: { Store.theme; return r.row.choices_from === "styles"
        && !!Store.theme.appearance && (Store.theme.appearance.overrides || []).length > 0 }
    // Escape: the preview goes back to the value it started from.
    function cancel() { if (previewing) Changes.putBack() }
    // Opens the row's dropdown (a select) without a pointer: the settings test hook uses it, as Enter does.
    function openControl(): void { if (ctl.item && ctl.item.open) ctl.item.open() }
    // Search jump target: one short glow, then nothing runs. Only a jump calls this, and a hidden row
    // skips it (Ma: no timer, no animation while the row is not on screen).
    function flash() { if (r.visible) flashAnim.restart() }
    // The keyboard focus goes to the row's control: a search hit or a breadcrumb reached by the keyboard lands on the setting.
    function focusControl(): void {
        const first = r.firstTabStop(ctl.item ? ctl.item : slot)
        if (first) first.forceActiveFocus()
    }
    function firstTabStop(item) {
        if (!item) return null
        if (item.activeFocusOnTab && item.visible && item.enabled !== false) return item
        const kids = item.children || []
        for (var i = 0; i < kids.length; i++) {
            const f = r.firstTabStop(kids[i])
            if (f) return f
        }
        return null
    }

    Item {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: r.stacked ? labels.implicitHeight + Theme.gap + ctlCol.implicitHeight
                                  : Math.max(labels.implicitHeight, ctlCol.implicitHeight)

        // --- label, help, and the chips that say what the row is ---------------------------------
        Column {
            id: labels
            width: r.stacked ? body.width : r.labelW
            spacing: 2
            Text {
                visible: r.stacked
                width: parent.width
                color: Theme.dim
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("settings.appearance." + (r.row.choices_from || "") + ".what")
            }
            Text {
                visible: !r.stacked
                width: parent.width
                color: r.inert ? Theme.dim : Theme.fg
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr(r.row.label)
            }
            Text {
                visible: text !== "" && !r.stacked
                width: parent.width
                color: Theme.dim
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: r.row.help ? I18n.tr(r.row.help) : ""
            }
            Row {
                visible: !r.stacked
                topPadding: 2
                spacing: 4
                Chip { visible: r.row.per_output; text: I18n.tr("settings.ui.per_output") }
                Chip { visible: r.row.restart; text: I18n.tr("settings.ui.restart"); edge: Theme.accent }
            }
        }

        // --- control, then its provenance line and the reasons ------------------------------------
        Column {
            id: ctlCol
            x: r.stacked ? 0 : r.labelW + Theme.pad
            y: r.stacked ? labels.implicitHeight + Theme.gap : 0
            width: body.width - x
            spacing: Theme.gap / 2

            Item {
                id: slot
                width: parent.width
                height: Math.max(ctl.item ? ctl.item.implicitHeight : 0, Theme.controlH)
                opacity: r.inert ? 0.5 : 1
                Loader {
                    id: ctl
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: r.row.control === "toggle" ? 40 : (r.cards ? slot.width : (r.wide ? Math.min(slot.width, 360) : ctl.implicitWidth))
                    sourceComponent: {
                        switch (r.row.control) {
                        case "toggle": return cToggle
                        case "slider": return cSlider
                        case "select": return r.cards ? cCards : (r.dropdown ? cDropdown : (r.switchChoice ? cSwitch : cSegmented))
                        case "pick_list": return cPickList
                        case "records": return cRecords
                        case "list": case "font": return cList
                        default: return cText   // number, text, color, action_binding
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: Math.max(chipRow.height, reset.height)
                Row {
                    id: chipRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.gap
                    ProvenanceChip {
                        visible: !r.previewing
                        prov: r.prov ?? ({})
                        key: r.row.key
                        output: r.out
                    }
                    Text {
                        visible: r.previewing
                        height: Theme.controlH
                        verticalAlignment: Text.AlignVCenter
                        color: Theme.dim
                        font.pixelSize: Theme.fs - 2
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("settings.preview.hint")
                    }
                    Button {
                        visible: r.previewing
                        primary: true
                        label: I18n.tr("settings.preview.keep")
                        onClicked: Changes.keep()
                    }
                    Button {
                        visible: r.previewing
                        label: I18n.tr("settings.preview.put_back")
                        onClicked: Changes.putBack()
                    }
                }
                ResetFlow {
                    id: reset
                    // Right after the chip, in the same line: the reset belongs to the value the chip names.
                    anchors.left: chipRow.right
                    anchors.leftMargin: Theme.gap
                    anchors.verticalCenter: chipRow.verticalCenter
                    visible: r.canReset && !r.previewing
                    enabled: Store.live
                    ops: [Store.resetOp(r.row.key, r.out)]
                    tag: r.row.key + (r.out !== "" ? "@" + r.out : "")
                    width: Math.min(parent.width - chipRow.width - Theme.gap, 420)
                }
            }

            // Why the control is inert, or its value is not in effect yet: one line each, with the link to the setting
            // that controls it (UX brief: "Controlled by High contrast → open").
            Repeater {
                model: r.reasons
                delegate: Row {
                    required property var modelData
                    spacing: Theme.gap
                    Text {
                        width: Math.min(implicitWidth, ctlCol.width - (link.visible ? link.width + Theme.gap : 0))
                        wrapMode: Text.WordWrap
                        color: Theme.dim
                        font.pixelSize: Theme.fs - 2
                        font.family: Theme.fam(text, Theme.families)
                        text: (modelData.kind === "pending" ? "↻ " : "⊘ ") + modelData.text
                    }
                    LinkText {
                        id: link
                        visible: !!modelData.key
                        text: I18n.tr("settings.ui.open")
                        onActivated: r.openKey(modelData.key)
                    }
                }
            }
            Text {
                visible: r.error !== "" && !r.fieldRefusal
                width: ctlCol.width
                wrapMode: Text.WordWrap
                color: Theme.error
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: "✕ " + I18n.tr("settings.ui.rejected") + ": " + r.error
            }
        }
    }

    Rectangle {
        id: glow
        anchors.fill: parent
        anchors.margins: -Theme.gap / 2
        radius: Theme.rSm
        color: Theme.accent
        opacity: 0
        z: -1
    }
    NumberAnimation {
        id: flashAnim
        target: glow
        property: "opacity"
        from: 0.35
        to: 0
        duration: 900
    }

    Rectangle {
        visible: r.divider
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.containerHigh
    }

    Component {
        id: cToggle
        Toggle {
            objectName: "toggle:" + r.row.key
            label: I18n.tr(r.row.label)
            checked: r.value === true
            enabled: r.editable
            onToggled: v => r.setValue(v)
        }
    }
    Component {
        id: cSlider
        Slider {
            objectName: "slider:" + r.row.key
            label: I18n.tr(r.row.label)
            value: Number(r.value)
            from: r.row.min ?? 0
            to: r.row.max ?? 1
            step: r.row.step ?? 0
            integer: r.row.type === "int"
            unit: r.row.unit ?? ""
            enabled: r.editable
            onCommitted: v => r.setValue(v)
            onPreviewed: v => r.moveTo(v)
            onCancelled: r.cancel()
        }
    }
    // Three or four fixed options: one pill each.
    Component {
        id: cSegmented
        Segmented {
            objectName: "segment:" + r.row.key
            choices: r.offers
            current: r.value
            enabled: r.editable
            onPicked: v => r.setValue(v)
            onPreviewed: v => r.moveTo(v)
            onCancelled: r.cancel()
        }
    }
    // Offers with looks of their own: preview cards (K45, I104), by category where the offers have one (W29).
    Component {
        id: cCards
        PackCards {
            objectName: "cards:" + r.row.key
            choices: r.offers
            looks: r.looks
            current: r.value
            enabled: r.editable
            previewOnMove: !r.packAction
            onPicked: v => r.setValue(v)
            onPreviewed: v => r.moveTo(v)
            onCancelled: r.cancel()
        }
    }
    // Two fixed options: a switch with both names visible.
    Component {
        id: cSwitch
        ChoiceSwitch {
            objectName: "switch:" + r.row.key
            label: I18n.tr(r.row.label)
            choices: r.offers
            current: r.value
            enabled: r.editable
            onPicked: v => r.setValue(v)
            onPreviewed: v => r.moveTo(v)
            onCancelled: r.cancel()
        }
    }
    // Offers from the daemon (or more than four): a dropdown. Moving the highlight in it changes nothing, unless the row
    // previews (then the value is shown); a pick is the change.
    Component {
        id: cDropdown
        Select {
            objectName: "select:" + r.row.key
            label: I18n.tr(r.row.label)
            choices: r.offers
            current: r.value
            enabled: r.editable
            onPicked: v => r.setValue(v)
            onPreviewed: v => { if (r.previewable) r.moveTo(v) }
            onCancelled: r.cancel()
        }
    }
    // An ordered subset of the offers (a string list with choices_from): one row per item, in order.
    Component {
        id: cPickList
        PickList {
            objectName: "pick:" + r.row.key
            label: I18n.tr(r.row.label)
            choices: r.offers
            items: Array.isArray(r.value) ? r.value : []
            enabled: r.editable
            refused: r.error !== ""
            onEdited: v => Store.setValue(r.row.key, v, r.out)
        }
    }
    // A list of records (K38): rows named by their item_label, a form with one control per declared field. Its changes are
    // one value each, like a pick list's; a refused field shows at the field (fieldRefusal).
    Component {
        id: cRecords
        RecordsEdit {
            objectName: "records:" + r.row.key
            label: I18n.tr(r.row.label)
            spec: r.row.record ?? ({})
            items: Array.isArray(r.value) ? r.value : []
            enabled: r.editable
            refusal: Store.fieldErrors[r.row.key] ?? null
            onEdited: v => Store.setValue(r.row.key, v, r.out)
            onCancelled: Store.clearRefusal(r.row.key)
        }
    }
    // A string list (chips), or the font chain (a list too; its edits are previews, UX brief settings 3).
    Component {
        id: cList
        ListEdit {
            objectName: "list:" + r.row.key
            label: I18n.tr(r.row.label)
            items: Array.isArray(r.value) ? r.value : []
            enabled: r.editable
            onEdited: v => { if (r.previewable) Changes.show(r.row.key, r.out, v, r.prov); else Store.setValue(r.row.key, v, r.out) }
            onKeepRequested: Changes.keep()
            onCancelled: r.cancel()
        }
    }
    Component {
        id: cText
        TextField {
            objectName: "text:" + r.row.key
            readonly property bool numeric: r.row.type === "int" || r.row.type === "float"
            readonly property bool isColor: r.row.control === "color"
            label: I18n.tr(r.row.label)
            width: Math.min(slot.width, 360)
            value: r.value === undefined ? "" : String(r.value)
            enabled: r.editable
            invalid: r.error !== ""
            mono: isColor || r.row.control === "action_binding"
            showSwatch: isColor
            swatch: isColor ? Qt.color(value) : "transparent"
            onAccepted: t => {
                var n = Number(t)
                r.setValue(numeric && t.trim() !== "" && !isNaN(n) ? n : t)
            }
        }
    }
}
