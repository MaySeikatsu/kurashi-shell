import QtQuick
import "../../core"
import "../island"
import "../decor"

// One zone of a top or bottom bar as a row of runs (surfaces/Bar.qml `runsOf`): each run one group block under chromes with
// groups — the island alone (its pill is its block), the window list a group of its own, every other stretch one group —
// `Theme.pad` + the groups' padding apart. A run's pieces are one module each, or a stretch of tight ones (the workspace
// keys and the sidebar button beside them). Runs and pieces with nothing present take no room (no spacing for them).
Row {
    id: zr
    required property var owner
    property string zone: "start"
    property var runs: []
    // Where the window list's room ends (the next zone's left edge, in this row's parent): the start zone's list fits up to it.
    property real limit: 0
    spacing: Theme.pad + 2 * zr.owner.groupInset
    // The group blocks' spans along the bar, in this row's parent (the bar's rule leaves a gap under them, I305).
    readonly property var groupSpans: {
        var out = []
        for (var i = 0; i < runRep.count; i++) {
            var r = runRep.itemAt(i)
            if (r && r.visible && r.grouped) out.push([zr.x + r.x + r.gx, zr.x + r.x + r.gx + r.gw])
        }
        return out
    }

    Repeater {
        id: runRep
        model: zr.runs
        delegate: Item {
            id: run
            required property var modelData
            property int presentN: 0
            // A group block, or the island's pill (its own block, I305).
            readonly property bool isle: modelData.kind === "island"
            readonly property bool grouped: grp.visible || (isle && Theme.groups && inner.width > 0)
            readonly property real gx: isle ? inner.x : grp.x
            readonly property real gw: isle ? inner.width : grp.width
            function recount() {
                var n = 0
                for (var i = 0; i < pieceRep.count; i++) { var p = pieceRep.itemAt(i); if (p && p.presentN > 0) n++ }
                if (n !== presentN) presentN = n
            }
            visible: presentN > 0
            width: inner.width
            height: zr.height
            BarGroup {
                id: grp
                around: inner
                visible: run.modelData.kind !== "island" && Theme.groups && inner.width > 0 && Theme.decor("bar.group", "block") !== "none"
                AnchorReport {
                    target: grp
                    key: run.modelData.key
                    output: zr.owner.outName
                    enabled: run.modelData.key !== "" && zr.owner.primary && grp.visible
                }
            }
            // W53 (row 591): the look's well round the group that holds the tray (9x's sunken notification area, XP's tray);
            // nothing is made while the look names none (TrayWell's `shown`).
            readonly property bool hasTray: run.modelData.pieces.some(function (p) {
                return p.entries.some(function (e) { return e.id === "tray" })
            })
            Loader {
                active: run.hasTray && (Theme.slot("tray") !== "" || Theme.decor("tray.sunken", false) === true)
                x: inner.x - grp.padX
                y: grp.y
                width: inner.width + 2 * grp.padX
                height: Theme.barH - 8
                sourceComponent: TrayWell { anchors.fill: parent }
            }
            Row {
                id: inner
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: run.modelData.kind === "island" ? 0 : -Theme.shadowDy / 2
                spacing: Theme.pad
                Repeater {
                    id: pieceRep
                    model: run.modelData.pieces
                    onItemAdded: Qt.callLater(run.recount)
                    onItemRemoved: Qt.callLater(run.recount)
                    delegate: Row {
                        id: piece
                        required property var modelData
                        property int presentN: 0
                        function recount() {
                            var n = 0
                            for (var i = 0; i < hostRep.count; i++) { var h = hostRep.itemAt(i); if (h && h.present) n++ }
                            if (n !== presentN) { presentN = n; run.recount() }
                        }
                        visible: presentN > 0
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                        spacing: modelData.tight ? zr.owner.tightSpacing : Theme.pad
                        Repeater {
                            id: hostRep
                            model: piece.modelData.entries
                            onItemAdded: Qt.callLater(piece.recount)
                            onItemRemoved: Qt.callLater(piece.recount)
                            delegate: ZoneHost {
                                required property var modelData
                                owner: zr.owner
                                entry: modelData
                                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                                // The window list's room: from where it stands to the next zone, less the gaps.
                                room: zr.zone === "start"
                                    ? zr.limit - (zr.x + run.x) - Theme.pad - 2 * zr.owner.groupInset
                                    : (zr.parent ? zr.parent.width / 4 : 0)
                                onPresentChanged: piece.recount()
                            }
                        }
                    }
                }
            }
        }
    }
}
