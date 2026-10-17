pragma ComponentBehavior: Bound
import QtQuick
import "format.js" as F

// The top processes (docs/ux/sysmon.md, "The process that matters"). One line per process: the name (elided; the full
// name and the pid are what a screen reader hears), the CPU and memory share, then End (SIGTERM: the program may save
// first) and Force quit (SIGKILL: unsaved work is lost). A process the mod may not end says why, in words under the
// row. Each signal is confirmed in place and names the signal. Shared by the panel and the Island's expanded view.
Column {
    id: list
    required property var store
    required property var theme
    required property var i18n
    // mod.sysmon.procs, as the daemon publishes it (undefined until the first scan)
    property var doc: undefined
    // The last refusal or failure, translated; empty when the last action worked.
    property string notice: ""
    // The confirmation open now: {pid, start, name, kind: "term" | "kill"}.
    property var pending: null

    function tr(key) {
        return i18n.tr(key)
    }

    // Rows are updated in place every refresh (a new document every 2 s), so keyboard focus and an open
    // confirmation survive it; a delegate is only created for a row that is new.
    ListModel {
        id: rows
    }

    function sync() {
        var procs = list.doc !== undefined && list.doc.procs !== undefined ? list.doc.procs : []
        for (var i = 0; i < procs.length; i++) {
            var p = procs[i]
            var row = {
                pid: p.pid,
                name: p.name,
                start: p.start,
                cpu: p.cpu !== undefined ? p.cpu : -1,
                mem: p.mem,
                can_end: p.can_end === true,
                end_reason: p.end_reason !== undefined ? p.end_reason : ""
            }
            if (i < rows.count) rows.set(i, row)
            else rows.append(row)
        }
        while (rows.count > procs.length) rows.remove(rows.count - 1)
    }

    onDocChanged: sync()
    Component.onCompleted: sync()

    width: parent ? parent.width : 328
    spacing: list.theme.xs

    Text {
        visible: rows.count === 0 && list.doc !== undefined
        width: list.width
        text: list.tr("sysmon.panel.no_procs")
        color: list.theme.dim
        font.pixelSize: list.theme.fsCaption
        font.family: list.theme.fam(text, list.theme.families)
    }

    Repeater {
        model: rows

        delegate: Column {
            id: row
            required property var modelData
            readonly property bool confirming: list.pending !== null && list.pending.pid === modelData.pid
                && list.pending.start === modelData.start
            width: list.width
            spacing: list.theme.xs

            // The one line: the name on the left (elided), the shares, then the two actions on the right.
            Item {
                width: row.width
                height: Math.max(buttons.implicitHeight, nameText.implicitHeight)

                Row {
                    id: buttons
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: list.theme.xs
                    PillButton {
                        theme: list.theme
                        label: list.tr("sysmon.panel.end")
                        available: row.modelData.can_end
                        reason: row.modelData.end_reason !== "" ? list.tr(row.modelData.end_reason) : ""
                        onActivated: list.pending = {pid: row.modelData.pid, start: row.modelData.start,
                            name: row.modelData.name, kind: "term"}
                    }
                    PillButton {
                        theme: list.theme
                        label: list.tr("sysmon.panel.force")
                        available: row.modelData.can_end
                        reason: row.modelData.end_reason !== "" ? list.tr(row.modelData.end_reason) : ""
                        onActivated: list.pending = {pid: row.modelData.pid, start: row.modelData.start,
                            name: row.modelData.name, kind: "kill"}
                    }
                }
                Text {
                    id: figures
                    anchors.right: buttons.left
                    anchors.rightMargin: list.theme.gap
                    anchors.verticalCenter: parent.verticalCenter
                    text: (row.modelData.cpu >= 0 ? F.pct(row.modelData.cpu) : "…") + " · " + F.pct(row.modelData.mem)
                    color: list.theme.dim
                    font.pixelSize: list.theme.fsCaption
                    font.family: list.theme.fam(text, list.theme.families)
                    font.features: ({"tnum": 1})
                    Accessible.role: Accessible.StaticText
                    Accessible.name: list.tr("sysmon.panel.cpu") + " " + (row.modelData.cpu >= 0 ? F.pct(row.modelData.cpu) : "…")
                        + ", " + list.tr("sysmon.panel.mem") + " " + F.pct(row.modelData.mem)
                }
                Text {
                    id: nameText
                    anchors.left: parent.left
                    anchors.right: figures.left
                    anchors.rightMargin: list.theme.gap
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.name
                    color: list.theme.fg
                    elide: Text.ElideRight
                    font.pixelSize: list.theme.fsLabel
                    font.family: list.theme.fam(text, list.theme.families)
                    Accessible.role: Accessible.StaticText
                    Accessible.name: row.modelData.name + ", pid " + row.modelData.pid
                }
            }

            // Why an end is not offered, in words (EPERM and the protected processes), under the row.
            Text {
                visible: !row.modelData.can_end && row.modelData.end_reason !== ""
                width: row.width
                text: row.modelData.end_reason !== "" ? list.tr(row.modelData.end_reason) : ""
                color: list.theme.dim
                wrapMode: Text.WordWrap
                font.pixelSize: list.theme.fsCaption
                font.family: list.theme.fam(text, list.theme.families)
            }

            // The question first (it names the signal), then the two answers.
            Column {
                visible: row.confirming
                width: row.width
                spacing: list.theme.xs

                Text {
                    width: parent.width
                    text: F.fill(list.tr(list.pending !== null && list.pending.kind === "kill"
                        ? "sysmon.panel.confirm_force" : "sysmon.panel.confirm_end"), {name: row.modelData.name})
                    color: list.theme.fg
                    wrapMode: Text.WordWrap
                    font.pixelSize: list.theme.fsCaption
                    font.family: list.theme.fam(text, list.theme.families)
                }
                Row {
                    spacing: list.theme.gap
                    PillButton {
                        theme: list.theme
                        label: list.tr("sysmon.panel.confirm")
                        active: true
                        onActivated: list.send(list.pending)
                    }
                    PillButton {
                        theme: list.theme
                        label: list.tr("sysmon.panel.cancel")
                        onActivated: list.pending = null
                    }
                }
            }
        }
    }

    Text {
        visible: list.notice !== ""
        width: list.width
        text: list.notice
        color: list.theme.error
        wrapMode: Text.WordWrap
        font.pixelSize: list.theme.fsCaption
        font.family: list.theme.fam(text, list.theme.families)
    }

    // The daemon checks pid and start time again before it signals, so a process that changed since the
    // list was drawn is refused, never signalled.
    function send(p) {
        if (p === null) return
        var action = p.kind === "kill" ? "sysmon.process.kill" : "sysmon.process.term"
        list.store.act(action, {pid: p.pid, start: p.start}, function (done, err) {
            list.pending = null
            list.notice = err ? list.tr(err.msg) : ""
        })
    }
}
