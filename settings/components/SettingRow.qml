import QtQuick
import "../core"

// DESIGN-SYSTEM §7 SettingRow: label · control · provenance chip · reset, plus reason lines when
// the control is inert and the daemon's rejection under the row. Generated from one schema row;
// nothing here knows a particular setting (rule 3).
Item {
    id: r
    property var row: ({})
    // Selected output for per_output rows ("" = all outputs).
    property string output: ""

    readonly property string out: row.per_output ? output : ""
    readonly property var prov: Store.prov(row.key, out)
    readonly property var value: prov === undefined ? row.default : prov.value
    readonly property var reasons: { Store.config; return Store.inertReasons(row, out) }
    // A pending restart, an offer that is gone (I9) and a mod that is off (K22) are not inertness: the value
    // can still be changed, and reset, meanwhile.
    readonly property bool inert: reasons.some(function (x) {
        return x.kind !== "pending" && x.kind !== "unavailable" && x.kind !== "mod_off"
    })
    readonly property bool editable: !inert && Store.live
    // A select with offers from the daemon (or more than four fixed ones) is a dropdown; four or fewer fixed
    // ones stay pills (BACKLOG I9).
    readonly property bool dropdown: row.control === "select" && !!(row.choices_from || (row.choices ?? []).length > 4)
    readonly property string error: Store.rowErrors[row.key] || ""
    readonly property bool canReset: prov !== undefined && prov.source && prov.source.kind === "user" && !inert

    implicitHeight: col.implicitHeight + Theme.gap * 2
    implicitWidth: 600

    function commit(v) { Store.setValue(row.key, v, out) }
    // Opens the row's dropdown (a select) without a pointer: the settings test hook uses it, as Enter does.
    function openControl(): void { if (ctl.item && ctl.item.open) ctl.item.open() }
    // Search jump target: one short glow, then nothing runs. Only a jump calls this, and a hidden row
    // skips it (Ma: no timer, no animation while the row is not on screen).
    function flash() { if (r.visible) flashAnim.restart() }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Item {
            id: head
            width: parent.width
            height: Math.max(labels.height, slot.height)

            Column {
                id: labels
                // A capped label column (UX review R.2 item 17): wide windows give the control the rest.
                width: Math.min(300, Math.max(160, parent.width * 0.36))
                spacing: 2
                Text {
                    width: parent.width
                    color: Theme.fg
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr(r.row.label)
                }
                Text {
                    visible: text !== ""
                    width: parent.width
                    color: Theme.dim
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fs - 2
                    font.family: Theme.fam(text, Theme.families)
                    text: r.row.help ? I18n.tr(r.row.help) : ""
                }
                Row {
                    spacing: 4
                    Chip { visible: r.row.per_output; text: I18n.tr("settings.ui.per_output") }
                    Chip { visible: r.row.restart; text: I18n.tr("settings.ui.restart"); edge: Theme.accent }
                }
            }

            Button {
                id: resetBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? implicitWidth : 0
                visible: r.canReset
                label: I18n.tr("settings.ui.reset")
                enabled: Store.live
                onClicked: Store.reset(r.row.key, r.out)
            }
            ProvenanceChip {
                id: chip
                anchors.right: resetBtn.left
                anchors.rightMargin: resetBtn.visible ? Theme.gap : 0
                anchors.verticalCenter: parent.verticalCenter
                prov: r.prov
            }
            Item {
                id: slot
                x: labels.width + Theme.pad
                width: head.width - x - chip.width - resetBtn.width - 2 * Theme.pad
                height: Math.max(ctl.item ? ctl.item.implicitHeight : 0, Theme.controlH)
                anchors.verticalCenter: parent.verticalCenter
                opacity: r.inert ? 0.5 : 1
                Loader {
                    id: ctl
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    // Toggles keep their natural width, a dropdown reads best at 320 px, everything else fills the slot.
                    width: r.row.control === "toggle" ? 40 : (r.dropdown ? Math.min(parent.width, 320) : parent.width)
                    sourceComponent: {
                        switch (r.row.control) {
                        case "toggle": return cToggle
                        case "slider": return cSlider
                        case "select": return r.dropdown ? cDropdown : cSegmented
                        case "pick_list": return cPickList
                        case "list": return cList
                        default: return cText   // number, text, font, color, action_binding
                        }
                    }
                }
            }
        }

        // Why the control is inert, or its value is not in effect yet (one line per reason).
        Repeater {
            model: r.reasons
            delegate: Text {
                required property var modelData
                width: col.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: (modelData.kind === "pending" ? "↻ " : "⊘ ") + modelData.text
            }
        }
        Text {
            visible: r.error !== ""
            width: col.width
            wrapMode: Text.WordWrap
            color: Theme.error
            font.pixelSize: Theme.fs - 2
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.rejected") + ": " + r.error
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
            onToggled: v => r.commit(v)
        }
    }
    Component {
        id: cSlider
        Slider {
            label: I18n.tr(r.row.label)
            value: Number(r.value)
            from: r.row.min ?? 0
            to: r.row.max ?? 1
            step: r.row.step ?? 0
            integer: r.row.type === "int"
            unit: r.row.unit ?? ""
            enabled: r.editable
            onCommitted: v => r.commit(v)
        }
    }
    // Four or fewer fixed options: one pill each.
    Component {
        id: cSegmented
        Segmented {
            choices: r.row.choices ?? []
            current: r.value
            enabled: r.editable
            onPicked: v => r.commit(v)
        }
    }
    // Offers from the daemon (or more than four): a dropdown.
    Component {
        id: cDropdown
        Select {
            objectName: "select:" + r.row.key
            label: I18n.tr(r.row.label)
            choices: r.row.choices ?? []
            current: r.value
            enabled: r.editable
            onPicked: v => r.commit(v)
        }
    }
    // An ordered subset of the offers (a string list with choices_from).
    Component {
        id: cPickList
        PickList {
            objectName: "pick:" + r.row.key
            label: I18n.tr(r.row.label)
            choices: r.row.choices ?? []
            items: Array.isArray(r.value) ? r.value : []
            enabled: r.editable
            onEdited: v => r.commit(v)
        }
    }
    Component {
        id: cList
        ListEdit {
            label: I18n.tr(r.row.label)
            items: Array.isArray(r.value) ? r.value : []
            enabled: r.editable
            onEdited: v => r.commit(v)
        }
    }
    Component {
        id: cText
        TextField {
            readonly property bool numeric: r.row.type === "int" || r.row.type === "float"
            readonly property bool isColor: r.row.control === "color"
            label: I18n.tr(r.row.label)
            width: 240
            value: r.value === undefined ? "" : String(r.value)
            enabled: r.editable
            mono: isColor || r.row.control === "action_binding"
            showSwatch: isColor
            swatch: isColor ? Qt.color(value) : "transparent"
            onAccepted: t => {
                var n = Number(t)
                r.commit(numeric && t.trim() !== "" && !isNaN(n) ? n : t)
            }
        }
    }
}
