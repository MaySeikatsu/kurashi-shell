import QtQuick
import "../core"

// Reset with its diff first (UX brief, settings 2): Reset plans the change with a dry run and lists what would change;
// Reset again makes it one undo step, Cancel drops the plan. `ops` are the reset ops; `done` follows a confirmed reset.
Column {
    id: f
    property var ops: []
    property bool enabled: true
    property string label: I18n.tr("settings.ui.reset")
    // Names the reset for the test hooks (objectName "reset:<tag>", "confirm:<tag>", "cancel:<tag>").
    property string tag: ""
    // "idle" (no plan), "planned" (the diff is listed), "failed" (the daemon would not plan it).
    property string phase: "idle"
    property var diff: []
    signal done()

    spacing: Theme.gap / 2

    // Focus follows the plan: the confirm (or, with nothing to confirm, Cancel) takes it, and Reset takes it back after.
    function plan() {
        Changes.planReset(f.ops, function (d) {
            f.diff = d || []
            f.phase = d === null ? "failed" : "planned"
            Qt.callLater(function () {
                if (f.phase === "planned" && f.diff.length > 0) confirmBtn.forceActiveFocus()
                else cancelBtn.forceActiveFocus()
            })
        })
    }
    function confirm() {
        Changes.applyReset(f.ops, function (m) {
            f.phase = "idle"
            if (m.t === "applied") f.done()
        })
    }
    function cancel() {
        f.phase = "idle"
        Qt.callLater(function () { resetBtn.forceActiveFocus() })
    }
    // One diff line: "Palette: Wa-iro → Kanso" (what it is now, what it becomes).
    function line(d) {
        var name = Store.labelOf(d.key) ? I18n.tr(Store.labelOf(d.key)) : d.key
        if (d.output) name += " (" + d.output + ")"
        var before = d.before ? Store.displayValue(d.before.value) : I18n.tr("settings.ui.not_set")
        var after = d.after ? Store.displayValue(d.after.value) : I18n.tr("settings.ui.not_set")
        return I18n.fmt("settings.ui.reset_line", { name: name, before: before, after: after })
    }

    Button {
        id: resetBtn
        objectName: "reset:" + f.tag
        visible: f.phase === "idle"
        label: f.label
        enabled: f.enabled && Store.live && f.ops.length > 0
        onClicked: f.plan()
    }
    Column {
        visible: f.phase !== "idle"
        width: parent.width
        spacing: Theme.gap / 2
        Repeater {
            model: f.phase === "planned" ? f.diff : []
            delegate: Text {
                required property var modelData
                width: f.width
                wrapMode: Text.WordWrap
                color: Theme.fg
                font.pixelSize: Theme.fs - 1
                font.family: Theme.fam(text, Theme.families)
                text: f.line(modelData)
            }
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            visible: f.phase === "planned" && f.diff.length === 0
            color: Theme.dim
            font.pixelSize: Theme.fs - 1
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.no_changes")
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            visible: f.phase === "failed"
            width: f.width
            wrapMode: Text.WordWrap
            color: Theme.error
            font.pixelSize: Theme.fs - 1
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.reset_failed")
        }
        Row {
            spacing: Theme.gap
            Button {
                id: confirmBtn
                objectName: "confirm:" + f.tag
                visible: f.phase === "planned" && f.diff.length > 0
                primary: true
                label: I18n.tr("settings.ui.reset_confirm")
                onClicked: f.confirm()
            }
            Button {
                id: cancelBtn
                objectName: "cancel:" + f.tag
                visible: f.phase !== "idle"
                label: I18n.tr("settings.ui.cancel")
                onClicked: f.cancel()
            }
        }
    }
}
