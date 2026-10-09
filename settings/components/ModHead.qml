import QtQuick
import "../core"
import "../components"

// The head of a mod's page (MODS.md "States, persistence and Settings"; UX brief, settings 5): the on/off switch first,
// then whether one of its services runs now, what it may do and what it costs, its description, and "Adds:" with a
// link to where each contribution shows. Everything shown is the daemon's. A forced `mods.enabled` makes the switch
// inert and says why; a refused request says why under the switch and stays until the mod changes state (B8).
Column {
    id: h
    property string modId: ""
    readonly property var entry: Store.modEntry(modId)
    readonly property string forced: Store.forcedReason("mods.enabled")
    readonly property bool invalid: !!entry && entry.state === "invalid"
    property string failure: ""
    // A "→ Island" link: the page where a contribution appears.
    signal pageRequested(string pageId)

    spacing: Theme.gap
    width: parent ? parent.width : 0

    // The switch sends the request. A refusal stays under it until any change goes through (B8).
    function setOn(on) {
        failure = ""
        Store.act(on ? "mod.enable" : "mod.disable", { id: modId }, function (m) {
            if (m.t !== "done") h.failure = Store.actError(m, "settings.err.unknown_action")
        })
    }
    Connections {
        target: Store
        function onChangeApplied() { h.failure = "" }
    }

    // --- the switch first, with its state in words (not colour alone): the name, then the switch beside it -------------
    Item {
        width: parent.width
        height: Math.max(title.implicitHeight, switchRow.height)
        Text {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - switchRow.width - Theme.pad * 2)
            elide: Text.ElideRight
            color: Theme.fg
            font.pixelSize: Theme.fsTitle
            font.bold: true
            font.family: Theme.fam(text, Theme.families)
            text: h.entry ? I18n.tr(h.entry.name) : ""
        }
        Row {
            id: switchRow
            anchors.left: title.right
            anchors.leftMargin: Theme.pad * 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.gap
            Toggle {
                id: sw
                objectName: "modpage:" + h.modId
                label: I18n.tr("settings.mods.enabled")
                checked: Store.modOn(h.modId)
                enabled: Store.live && h.forced === "" && h.entry !== null && !h.invalid
                onToggled: v => h.setOn(v)
            }
            Text {
                height: Theme.controlH
                verticalAlignment: Text.AlignVCenter
                color: Theme.dim
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: Store.modOn(h.modId) ? I18n.tr("settings.ui.on") : I18n.tr("settings.ui.off")
            }
        }
    }
    Text {
        visible: h.forced !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fs - 2
        font.family: Theme.fam(text, Theme.families)
        text: "⊘ " + h.forced
    }
    Text {
        visible: h.failure !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        color: Theme.error
        font.pixelSize: Theme.fs - 2
        font.family: Theme.fam(text, Theme.families)
        text: "✕ " + I18n.tr("settings.ui.mods_failed") + ": " + h.failure
    }

    // --- what it is, does and costs --------------------------------------------------------------------
    Text {
        visible: h.entry !== null && h.entry.running !== undefined
        width: parent.width
        color: h.entry && h.entry.running ? Theme.fg : Theme.dim
        font.pixelSize: Theme.fs - 1
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr(h.entry && h.entry.running ? "settings.mods.running_yes" : "settings.mods.running_no")
    }
    Text {
        visible: !!h.entry && !!h.entry.description
        width: parent.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fs - 1
        font.family: Theme.fam(text, Theme.families)
        text: h.entry && h.entry.description ? I18n.tr(h.entry.description) : ""
    }
    Text {
        visible: !!h.entry
        width: parent.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fs - 2
        font.family: Theme.fam(text, Theme.families)
        text: h.entry ? I18n.tr("settings.ui.mod_caps") + ": " + Store.joinedWords(h.entry.capabilities, "settings.ui.cap.")
            + "    " + I18n.tr("settings.ui.mod_cost") + ": " + Store.word("settings.ui.cost.", h.entry.cost || "") : ""
    }

    // --- Adds: what it contributes, each with a link where it shows (UX brief, settings 5) -----------------
    Flow {
        id: adds
        visible: !!h.entry && (h.entry.provides || []).length > 0
        width: parent.width
        spacing: Theme.gap
        Text {
            height: Theme.controlH - 8
            verticalAlignment: Text.AlignVCenter
            color: Theme.dim
            font.pixelSize: Theme.fs - 2
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.mod_adds") + ":"
        }
        Repeater {
            model: h.entry ? (h.entry.provides || []) : []
            delegate: Row {
                required property var modelData
                spacing: 4
                Text {
                    height: Theme.controlH - 8
                    verticalAlignment: Text.AlignVCenter
                    color: Theme.fg
                    font.pixelSize: Theme.fs - 2
                    font.family: Theme.fam(text, Theme.families)
                    text: Store.addsLabel(modelData)
                }
                LinkText {
                    visible: Store.addsPage(modelData) !== ""
                    text: "→ " + I18n.tr("settings.page." + Store.addsPage(modelData))
                    onActivated: h.pageRequested(Store.addsPage(modelData))
                }
            }
        }
    }
}
