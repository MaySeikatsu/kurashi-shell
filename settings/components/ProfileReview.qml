import QtQuick
import "../core"
import "ProfileDiff.js" as ProfileDiff

// What a profile would do (UX brief, settings 6), shared by the Revert preview and the import review: the settings whose
// value changes (ProfileDiffRow), the ones that only move to the profile (same value, listed apart), the ones a forced
// layer holds back ("not applied", with the reason), how many of your own changes stay, and what a file skipped. Every
// line is the daemon's answer; this view only lays it out.
Column {
    id: v
    property var entries: []
    property var held: []
    property int kept: 0
    property var diagnostics: []
    spacing: Theme.gap / 2
    readonly property var valueLines: entries.filter(ProfileDiff.changesValue)
    readonly property var sameLines: entries.filter(ProfileDiff.sameValue)

    // "config.diag.<kind>" names what the file skipped. A message is shown only as a catalog key: the parser's own
    // English (a syntax error) never reaches the page (K27).
    function diagText(d) {
        var reason = d.reason || ({})
        var text = I18n.tr("config.diag." + (reason.kind || "invalid"))
        if (reason.message && I18n.has(reason.message)) text += " (" + I18n.tr(reason.message) + ")"
        return (d.key ? d.key + ": " : "") + text
    }

    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: v.valueLines.length === 0
        width: v.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("settings.ui.no_changes")
    }
    Repeater {
        model: v.valueLines
        delegate: ProfileDiffRow {
            required property var modelData
            width: v.width
            entry: modelData
        }
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: v.sameLines.length > 0
        width: v.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fs - 1
        font.bold: true
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("settings.ui.profile_same_head")
    }
    Repeater {
        model: v.sameLines
        delegate: ProfileDiffRow {
            required property var modelData
            width: v.width
            entry: modelData
        }
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: v.held.length > 0
        color: Theme.dim
        font.pixelSize: Theme.fs - 1
        font.bold: true
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("settings.ui.not_applied_head")
    }
    Repeater {
        model: v.held
        delegate: Text {
            required property var modelData
            width: v.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs - 1
            font.family: Theme.fam(text, Theme.families)
            text: "⊘ " + I18n.tr(Store.labelOf(modelData.key))
                + (modelData.output ? " (" + modelData.output + ")" : "")
                + " — " + Store.forcedText({ reason: modelData.reason, forced_by: modelData.forced_by })
        }
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        width: v.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fs - 1
        font.family: Theme.fam(text, Theme.families)
        text: I18n.fmt("settings.ui.profile_kept", { n: v.kept })
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: v.diagnostics.length > 0
        color: Theme.dim
        font.pixelSize: Theme.fs - 1
        font.bold: true
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("settings.ui.import_skipped")
    }
    Repeater {
        model: v.diagnostics
        delegate: Text {
            required property var modelData
            width: v.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs - 1
            font.family: Theme.fam(text, Theme.families)
            text: v.diagText(modelData)
        }
    }
}
