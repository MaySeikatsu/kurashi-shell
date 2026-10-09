import QtQuick
import "../core"

// The head of a mod's page (MODS.md "States, persistence and Settings"): its on/off switch, which asks the
// daemon for `mod.enable` or `mod.disable`; its description; and whether one of its services runs now. Everything
// shown is the daemon's. A forced `mods.enabled` makes the switch inert and says why; a refused request says why
// under the switch.
Column {
    id: h
    property string modId: ""
    readonly property var entry: Store.modEntry(modId)
    readonly property string forced: Store.forcedReason("mods.enabled")
    property string failure: ""

    spacing: Theme.gap

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

    Item {
        id: top
        width: h.width
        height: Math.max(info.implicitHeight, sw.height)

        Column {
            id: info
            anchors.left: parent.left
            anchors.right: sw.left
            anchors.rightMargin: Theme.pad
            spacing: 2
            Text {
                width: parent.width
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.bold: true
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("settings.mods.enabled")
            }
            Text {
                visible: text !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fs - 1
                font.family: Theme.fam(text, Theme.families)
                text: h.entry && h.entry.description ? I18n.tr(h.entry.description) : ""
            }
            Text {
                width: parent.width
                color: Theme.dim
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr(h.entry && h.entry.running ? "settings.mods.running_yes" : "settings.mods.running_no")
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
                text: I18n.tr("settings.ui.mods_failed") + ": " + h.failure
            }
        }
        Toggle {
            id: sw
            objectName: "modpage:" + h.modId
            label: I18n.tr("settings.mods.enabled")
            anchors.right: parent.right
            anchors.top: parent.top
            checked: Store.modOn(h.modId)
            enabled: Store.live && h.forced === "" && h.entry !== null && h.entry.state !== "invalid"
            onToggled: v => h.setOn(v)
        }
    }
}
