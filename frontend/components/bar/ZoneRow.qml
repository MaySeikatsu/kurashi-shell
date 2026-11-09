import QtQuick
import "../../core"
import "../island"
import "../decor"

// One zone of a top or bottom bar as a row of runs (surfaces/Bar.qml `runsOf`): each run one group block under chromes with
// groups — the island alone (its pill is its block), the window list a group of its own, every other stretch one group —
// `Theme.pad` + the groups' padding apart. A run's pieces are one module each, or a stretch of tight ones (the workspace
// keys and the sidebar button beside them). Runs and pieces with nothing shown take no room (no spacing for them).
// B48 (docs/ux/bar-fit.md): the bar lays its three zones out as one (components/bar/barfit.js); this row hands it its view
// (`spec`) and is handed back each module's `compact`, `room` and `parked`.
Row {
    id: zr
    required property var owner
    property string zone: "start"
    property var runs: []
    // How many of this zone's modules the bar's fit put in the overflow; the "…" button stands at the zone's inner end
    // while there are any (the start and centre zones' last place, the end zone's first).
    property int parkedN: 0
    readonly property bool overflowFirst: zone === "end"
    // W53.3 (`[decor] bar.gap`): a look's own gap between runs and modules (11's taskbar packs its keys 4 px apart).
    readonly property int barGap: Theme.decor("bar.gap", -1)
    spacing: barGap >= 0 ? barGap : Theme.pad + 2 * zr.owner.groupInset
    // The group blocks' spans along the bar, in this row's parent (the bar's rule leaves a gap under them, I305).
    readonly property var groupSpans: {
        var out = []
        for (var i = 0; i < runRep.count; i++) {
            var r = runRep.itemAt(i)
            if (r && r.visible && r.grouped) out.push([zr.x + r.x + r.gx, zr.x + r.x + r.gx + r.gw])
        }
        return out
    }
    // The overflow button, when it stands here (its width is the fit's `overflowW`).
    readonly property Item overflowItem: overflowFirst ? (ovFirst.item || null) : (ovLast.item || null)

    Loader {
        id: ovFirst
        active: zr.overflowFirst && zr.parkedN > 0
        visible: active
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        sourceComponent: overflowButton
    }
    Repeater {
        id: runRep
        model: zr.runs
        delegate: Item {
            id: run
            required property var modelData
            property int presentN: 0
            property alias pieceRepeater: pieceRep
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
                spacing: zr.barGap >= 0 ? zr.barGap : Theme.pad
                Repeater {
                    id: pieceRep
                    model: run.modelData.pieces
                    onItemAdded: Qt.callLater(run.recount)
                    onItemRemoved: Qt.callLater(run.recount)
                    delegate: Row {
                        id: piece
                        required property var modelData
                        property int presentN: 0
                        property alias hostRepeater: hostRep
                        function recount() {
                            var n = 0
                            for (var i = 0; i < hostRep.count; i++) { var h = hostRep.itemAt(i); if (h && h.shown) n++ }
                            if (n !== presentN) { presentN = n; run.recount() }
                        }
                        visible: presentN > 0
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                        spacing: modelData.tight ? zr.owner.tightSpacing : (zr.barGap >= 0 ? zr.barGap : Theme.pad)
                        Repeater {
                            id: hostRep
                            model: piece.modelData.entries
                            onItemAdded: { Qt.callLater(piece.recount); zr.owner.requestFit() }
                            onItemRemoved: { Qt.callLater(piece.recount); zr.owner.requestFit() }
                            delegate: ZoneHost {
                                required property var modelData
                                owner: zr.owner
                                entry: modelData
                                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                                // (`room`, `compact` and `parked` are the bar's fit's, written by Bar.qml's refit)
                                onShownChanged: piece.recount()
                            }
                        }
                    }
                }
            }
        }
    }
    Loader {
        id: ovLast
        active: !zr.overflowFirst && zr.parkedN > 0
        visible: active
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        sourceComponent: overflowButton
    }
    Component {
        id: overflowButton
        OverflowButton {
            id: ob
            count: zr.parkedN
            zone: zr.zone
            output: zr.owner.outName
            open: zr.owner.overflowZone === zr.zone
            onClicked: zr.owner.openOverflow(zr.zone, ob)
        }
    }

    // ---- the fit's view of this zone (barfit.js `Z`): its runs, pieces and present modules, with the gaps it lays them
    // out with; and the hosts the answer is written to ----
    function eachHost(fn) {
        for (var i = 0; i < runRep.count; i++) {
            var r = runRep.itemAt(i)
            if (!r) continue
            for (var j = 0; j < r.pieceRepeater.count; j++) {
                var p = r.pieceRepeater.itemAt(j)
                if (!p) continue
                for (var k = 0; k < p.hostRepeater.count; k++) {
                    var h = p.hostRepeater.itemAt(k)
                    if (h) fn(h)
                }
            }
        }
    }
    function keyOf(h) { return zr.zone + "/" + h.mid }
    function spec() {
        var runsOut = []
        for (var i = 0; i < runRep.count; i++) {
            var r = runRep.itemAt(i)
            if (!r) continue
            var piecesOut = []
            for (var j = 0; j < r.pieceRepeater.count; j++) {
                var p = r.pieceRepeater.itemAt(j)
                if (!p) continue
                var hostsOut = []
                for (var k = 0; k < p.hostRepeater.count; k++) {
                    var h = p.hostRepeater.itemAt(k)
                    if (!h || !h.present || h.fitSlots <= 0) continue
                    hostsOut.push({ key: keyOf(h), id: h.mid, full: h.keptFull, compact: h.keptCompact, min: h.keptMin,
                                    elastic: h.keptElastic })
                }
                piecesOut.push({ hostGap: p.spacing, hosts: hostsOut })
            }
            runsOut.push({ pieceGap: zr.barGap >= 0 ? zr.barGap : Theme.pad, pieces: piecesOut })
        }
        return { runGap: zr.spacing, runs: runsOut }
    }
}
