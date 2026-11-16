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
        Label {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - switchRow.width - Theme.pad * 2)
            elide: Text.ElideRight
            font.pixelSize: Theme.fsTitle
            font.bold: true
            text: h.entry ? I18n.tr(h.entry.name) : ""
        }
        Row {
            id: switchRow
            anchors.left: title.right
            anchors.leftMargin: Theme.pad * 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.gap
            // K102: a mod with a panel opens from here: turning it on is not the end of finding it.
            Button {
                readonly property string panel: {
                    if (!h.entry || h.entry.state !== "enabled") return ""
                    var l = (h.entry.provides || []).filter(function (p) { return String(p).indexOf("panel:") === 0 })
                    return l.length > 0 ? String(l[0]).substring(6) : ""
                }
                objectName: "mod-open:" + h.modId
                visible: panel !== ""
                anchors.verticalCenter: parent.verticalCenter
                label: I18n.tr("settings.ui.mod_open")
                enabled: Store.live
                onClicked: Store.act("mod.panel.open", { id: h.modId, panel: panel })
            }
            Toggle {
                id: sw
                objectName: "modpage:" + h.modId
                label: I18n.tr("settings.mods.enabled")
                checked: Store.modOn(h.modId)
                enabled: Store.live && h.forced === "" && h.entry !== null && !h.invalid
                onToggled: v => h.setOn(v)
            }
            Label {
                height: Theme.controlH
                verticalAlignment: Text.AlignVCenter
                dim: true
                text: Store.modOn(h.modId) ? I18n.tr("settings.ui.on") : I18n.tr("settings.ui.off")
            }
        }
    }
    Label {
        visible: h.forced !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        dim: true
        font.pixelSize: Theme.fs - 2
        text: "⊘ " + h.forced
    }
    Label {
        visible: h.failure !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        color: Theme.error
        font.pixelSize: Theme.fs - 2
        text: "✕ " + I18n.tr("settings.ui.mods_failed") + ": " + h.failure
    }

    // --- what it is, does and costs --------------------------------------------------------------------
    // "Running now" names what it runs for (I48, docs/ux/settings.md): a job with nothing to do is not listed.
    Label {
        visible: h.entry !== null && h.entry.running !== undefined
        width: parent.width
        wrapMode: Text.WordWrap
        color: h.entry && h.entry.running ? Theme.fg : Theme.dim
        font.pixelSize: Theme.fs - 1
        text: h.entry && (h.entry.running_reasons || []).length > 0
            ? I18n.fmt("settings.mods.running_now", { reasons: Store.joinedWords(h.entry.running_reasons, "") })
            : I18n.tr("settings.mods.not_running")
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }
    Label {
        visible: !!h.entry && !!h.entry.description
        width: parent.width
        wrapMode: Text.WordWrap
        dim: true
        font.pixelSize: Theme.fs - 1
        text: h.entry && h.entry.description ? I18n.tr(h.entry.description) : ""
    }
    Label {
        visible: !!h.entry
        width: parent.width
        wrapMode: Text.WordWrap
        dim: true
        font.pixelSize: Theme.fs - 2
        text: h.entry ? I18n.tr("settings.ui.mod_caps") + ": " + Store.joinedWords(h.entry.capabilities, "settings.ui.cap.")
            + "    " + I18n.tr("settings.ui.mod_cost") + ": " + Store.word("settings.ui.cost.", h.entry.cost || "") : ""
    }

    // K155 (W93): a mod whose code is a program of its own says so where it is switched on, with the program's name
    // (Shōjiki; MODS.md "Host programs": it is the user's code, running as the user).
    Label {
        readonly property var hosts: (h.entry && h.entry.hosts) || []
        visible: hosts.length > 0
        width: parent.width
        wrapMode: Text.WordWrap
        color: Theme.warning
        font.pixelSize: Theme.fs - 1
        text: hosts.length > 0
            ? I18n.tr("settings.ui.mod_runs_program").replace("{program}", hosts.map(function (x) { return x.exec }).join(", "))
            : ""
        Accessible.name: text
    }

    // --- Adds: what it contributes, each with a link where it shows (UX brief, settings 5) -----------------
    Flow {
        id: adds
        visible: !!h.entry && (h.entry.provides || []).length > 0
        width: parent.width
        spacing: Theme.gap
        Label {
            height: Theme.controlH - 8
            verticalAlignment: Text.AlignVCenter
            dim: true
            font.pixelSize: Theme.fs - 2
            text: I18n.tr("settings.ui.mod_adds") + ":"
        }
        Repeater {
            model: h.entry ? (h.entry.provides || []) : []
            delegate: Row {
                required property var modelData
                spacing: 4
                Label {
                    height: Theme.controlH - 8
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: Theme.fs - 2
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
