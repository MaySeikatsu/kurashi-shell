import QtQuick
import "../core"
import "../components"

// Changed (UX brief, settings 2): every setting that differs from the defaults because the user, a profile or Nix set
// it, across pages and outputs. Each row names its layer and links to its page; a row the user set has a Reset that shows
// the diff first. A page group has its own reset, the page a reset for all of them at the top (each one a single change).
Flickable {
    id: p
    signal jumpRequested(string targetPage, var row)

    // The changed settings grouped by page, in page order: [{pageId, label, entries: [{key, output, row, prov}]}].
    readonly property var groups: {
        Store.config
        var out = []
        var byPage = {}
        var list = Store.changedEntries()
        for (var i = 0; i < list.length; i++) {
            var e = list[i]
            if (byPage[e.pageId] === undefined) {
                var pg = { pageId: e.pageId, label: Store.pageLabel(e.pageId), entries: [] }
                byPage[e.pageId] = pg
                out.push(pg)
            }
            byPage[e.pageId].entries.push({ key: e.row.key, output: e.output, row: e.row, prov: e.prov })
        }
        return out
    }
    // The count of changed settings, and the user-set ones among them (the ones a reset can undo).
    readonly property int changedCount: { var n = 0; for (var i = 0; i < groups.length; i++) n += groups[i].entries.length; return n }
    readonly property var allUserOps: {
        Store.config
        return Store.userSetEntries().map(function (e) { return Store.resetOp(e.key, e.output) })
    }
    // The reset ops of one group: the user-set entries on that page.
    function groupOps(g) {
        var out = []
        for (var i = 0; i < g.entries.length; i++) {
            var e = g.entries[i]
            if (e.prov && e.prov.source && e.prov.source.kind === "user") out.push(Store.resetOp(e.key, e.output))
        }
        return out
    }

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
            width: col.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.changed_help")
        }
        Text {
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
            label: I18n.fmt("settings.ui.reset_all", { n: p.allUserOps.length })
        }

        Repeater {
            model: p.groups
            delegate: Column {
                id: group
                required property var modelData
                readonly property var ops: p.groupOps(modelData)
                width: col.width
                spacing: Theme.gap / 2

                Row {
                    spacing: Theme.gap
                    Text {
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
                        width: group.width
                        readonly property bool userSet: modelData.prov && modelData.prov.source && modelData.prov.source.kind === "user"
                        height: Math.max(name.implicitHeight, chipBox.height) + (userSet ? resetBox.height + Theme.gap / 2 : 0)
                            + Theme.gap

                        Text {
                            id: name
                            anchors.left: parent.left
                            anchors.right: value.left
                            anchors.rightMargin: Theme.pad
                            anchors.top: parent.top
                            anchors.topMargin: 6
                            wrapMode: Text.WordWrap
                            color: Theme.fg
                            font.pixelSize: Theme.fs
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.tr(entry.modelData.row.label) + (entry.modelData.output ? " (" + entry.modelData.output + ")" : "")
                        }
                        Text {
                            id: value
                            anchors.right: chipBox.left
                            anchors.rightMargin: Theme.pad
                            anchors.top: parent.top
                            anchors.topMargin: 6
                            width: Math.min(implicitWidth, 200)
                            elide: Text.ElideRight
                            color: Theme.fg
                            font.pixelSize: Theme.fs
                            font.family: Theme.fam(text, Theme.families)
                            text: Store.displayValue(entry.modelData.prov.value)
                        }
                        Item {
                            id: chipBox
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.topMargin: 4
                            width: chip.width + Theme.gap + openLink.width
                            height: Math.max(chip.height, openLink.height)
                            ProvenanceChip {
                                id: chip
                                anchors.left: parent.left
                                prov: entry.modelData.prov
                                key: entry.modelData.key
                                output: entry.modelData.output
                            }
                            LinkText {
                                id: openLink
                                anchors.right: parent.right
                                anchors.verticalCenter: chip.verticalCenter
                                text: I18n.tr("settings.ui.open")
                                onActivated: p.jumpRequested(group.modelData.pageId, entry.modelData.row)
                            }
                        }
                        ResetFlow {
                            id: resetBox
                            anchors.right: parent.right
                            anchors.top: chipBox.bottom
                            anchors.topMargin: Theme.gap / 2
                            visible: entry.userSet
                            enabled: Store.live
                            ops: [Store.resetOp(entry.modelData.key, entry.modelData.output)]
                        }
                    }
                }
                ResetFlow {
                    visible: group.ops.length > 1
                    ops: group.ops
                    enabled: Store.live
                    label: I18n.fmt("settings.ui.reset_page_group", { page: group.modelData.label, n: group.ops.length })
                }
            }
        }
    }
}
