import QtQuick
import QtQuick.Controls.Basic as QQC
import "../core"
import "../components"

// Changed (UX brief, settings 2): every setting that differs from the defaults because the user, a profile or Nix set
// it, across pages and outputs. Each row names its layer and links to its page; a row the user set has a Reset that shows
// the diff first. A page group has its own reset, the page a reset for all of them at the top (each one a single change).
// The rows are rebuilt only when the set of changed settings changes; a value change is read live by each row, so the
// focus on a Reset stays where it is while the daemon answers.
Flickable {
    id: p
    // Kinetic wheel and a grabbable scrollbar (session 17, docs/ux/settings.md).
    flickDeceleration: 2900
    maximumFlickVelocity: 7000
    KineticWheel { flick: p }
    QQC.ScrollBar.vertical: PageScrollBar {}
    signal jumpRequested(string targetPage, var row)

    // The changed settings grouped by page, in page order: [{pageId, label, entries: [{key, output}]}]. Replaced only when
    // the set of changed settings changes (refreshStructure).
    property var structure: []
    property string structureSig: ""
    function refreshStructure() {
        var list = Store.changedEntries()
        var groups = []
        var byPage = {}
        for (var i = 0; i < list.length; i++) {
            var e = list[i]
            if (byPage[e.pageId] === undefined) {
                var pg = { pageId: e.pageId, label: Store.pageLabel(e.pageId), entries: [] }
                byPage[e.pageId] = pg
                groups.push(pg)
            }
            byPage[e.pageId].entries.push({ key: e.row.key, output: e.output, held: e.held === true })
        }
        var sig = JSON.stringify(groups)
        if (sig !== structureSig) {
            structureSig = sig
            structure = groups
        }
    }
    // The values, the schema's pages and labels and the catalogue (the page titles) decide the list, and any of them may
    // arrive first: the list is rebuilt when one of them changes.
    Component.onCompleted: refreshStructure()
    Connections {
        target: Store
        function onConfigChanged() { p.refreshStructure() }
        function onSchemaChanged() { p.refreshStructure() }
        function onI18nChanged() { p.refreshStructure() }
        function onHeldUsersChanged() { p.refreshStructure() }
    }

    // The count of changed settings, and the ones the user set (the ones a reset can undo).
    readonly property int changedCount: {
        var n = 0
        for (var i = 0; i < structure.length; i++) n += structure[i].entries.length
        return n
    }
    readonly property var allUserOps: {
        Store.config
        return Store.userSetEntries().map(function (e) { return Store.resetOp(e.key, e.output) })
    }
    // The reset ops of one group: the user-set entries on that page, read live.
    function groupOps(g) {
        var out = []
        for (var i = 0; i < g.entries.length; i++) {
            var e = g.entries[i]
            var q = Store.prov(e.key, e.output)
            if (q && q.source && q.source.kind === "user") out.push(Store.resetOp(e.key, e.output))
        }
        return out
    }
    // A row's link: the page it is on, with the row in view.
    function openKey(pageId, key) {
        var h = Store.rowOf(key)
        if (h) p.jumpRequested(pageId, h.row)
    }
    // The name column's width: the value, the layer and the link line up in one column across the rows.
    readonly property real labelW: Math.min(320, Math.max(220, width * 0.3))

    contentWidth: width
    contentHeight: col.implicitHeight + Theme.pad * 2
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
        id: col
        x: Theme.pad
        y: Theme.pad
        width: p.width - 2 * Theme.pad
        spacing: Theme.pad

        PageHeader {
            width: col.width
            text: I18n.tr("settings.ui.changed")
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            width: col.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.changed_help")
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            visible: p.changedCount === 0
            width: col.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.changed_empty")
        }
        ResetFlow {
            visible: p.allUserOps.length > 1
            ops: p.allUserOps
            enabled: Store.live
            tag: "changed"
            label: I18n.fmt("settings.ui.reset_all", { n: p.allUserOps.length })
        }

        Repeater {
            model: p.structure
            delegate: Column {
                id: group
                required property var modelData
                readonly property var ops: p.groupOps(group.modelData)
                width: col.width
                spacing: Theme.gap / 2

                Row {
                    spacing: Theme.gap
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        topPadding: Theme.gap
                        color: Theme.dim
                        font.pixelSize: Theme.fs
                        font.bold: true
                        font.family: Theme.fam(text, Theme.families)
                        text: group.modelData.label + "  ·  " + group.modelData.entries.length
                    }
                }
                Repeater {
                    model: group.modelData.entries
                    delegate: Item {
                        id: entry
                        required property var modelData
                        // The value and the layer are read live: a change the daemon makes updates this row in place. A held-back
                        // row shows the user's value, which a forced layer keeps out of effect (I64 (3)); the line under it says so.
                        readonly property var effective: Store.prov(entry.modelData.key, entry.modelData.output) || ({})
                        readonly property var prov: entry.modelData.held
                            ? (Store.heldUserOf(entry.modelData.key, entry.modelData.output) || ({})) : entry.effective
                        readonly property bool userSet: !entry.modelData.held && !!entry.prov.source && entry.prov.source.kind === "user"
                        readonly property var row: { Store.schema; var h = Store.rowOf(entry.modelData.key); return h ? h.row : ({}) }
                        readonly property real valueX: p.labelW + Theme.pad
                        width: group.width
                        height: Math.max(name.implicitHeight, line.height)
                            + (entry.userSet ? resetBox.height + Theme.gap / 2 : 0)
                            + (entry.modelData.held ? heldLine.height + Theme.gap / 2 : 0) + Theme.gap

                        Text {
                            id: name
                            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                            x: 0
                            y: 6
                            width: p.labelW
                            elide: Text.ElideRight
                            color: Theme.fg
                            font.pixelSize: Theme.fs
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.tr(entry.row.label) + (entry.modelData.output ? " (" + entry.modelData.output + ")" : "")
                        }
                        Row {
                            id: line
                            x: entry.valueX
                            y: 4
                            spacing: Theme.gap
                            Text {
                                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                                height: Theme.controlH - 8
                                verticalAlignment: Text.AlignVCenter
                                width: Math.min(implicitWidth, 200)
                                elide: Text.ElideRight
                                color: Theme.fg
                                font.pixelSize: Theme.fs
                                font.family: Theme.fam(text, Theme.families)
                                text: entry.prov.value !== undefined ? Store.displayValue(entry.prov.value) : ""
                            }
                            ProvenanceChip {
                                prov: entry.prov
                                key: entry.modelData.key
                                output: entry.modelData.output
                            }
                            LinkText {
                                text: I18n.tr("settings.ui.open")
                                onActivated: p.openKey(group.modelData.pageId, entry.modelData.key)
                            }
                        }
                        // Under the value column: the diff of a planned reset is as wide as the rows allow.
                        ResetFlow {
                            id: resetBox
                            x: entry.valueX
                            y: line.height + Theme.gap / 2 + 4
                            width: Math.min(entry.width - entry.valueX, 480)
                            visible: entry.userSet
                            enabled: Store.live
                            ops: [Store.resetOp(entry.modelData.key, entry.modelData.output)]
                            tag: entry.modelData.key + (entry.modelData.output ? "@" + entry.modelData.output : "")
                        }
                        // A held-back value: the layer that keeps it out of effect, and the value in effect (I64 (3)). No Reset
                        // here: a forced value is read-only (UX brief, settings: nix-forced), and resetting the held one changes
                        // nothing in effect.
                        Text {
                            id: heldLine
                            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                            x: entry.valueX
                            y: line.height + Theme.gap / 2 + 4
                            width: Math.min(entry.width - entry.valueX, 480)
                            visible: entry.modelData.held === true
                            wrapMode: Text.WordWrap
                            color: Theme.dim
                            font.pixelSize: Theme.fs - 1
                            font.family: Theme.fam(text, Theme.families)
                            text: entry.modelData.held === true
                                ? I18n.fmt("settings.ui.held_back", { reason: Store.forcedText(entry.effective),
                                                                       value: Store.displayValue(entry.effective.value) })
                                : ""
                        }
                    }
                }
                ResetFlow {
                    visible: group.ops.length > 1
                    ops: group.ops
                    enabled: Store.live
                    tag: "group:" + group.modelData.pageId
                    label: I18n.fmt("settings.ui.reset_page_group", { page: group.modelData.label, n: group.ops.length })
                }
            }
        }
    }
}
