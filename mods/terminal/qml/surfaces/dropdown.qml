import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.components
import "../"

// The terminal's drop-down on one output (`surface:dropdown`; docs/ux/terminal.md "The places"). The shell draws the
// sheet — joined to the main bar's centre (`place = bar`) or an edge as the bar's cards are (JoinedCard), or a floating
// card (`center`, `position`) — its tab row and its grip; the terminal host lays its text over the well (`terminal.place`
// reports where the well rests; while the sheet moves the report is withdrawn and the host's window unmaps). Unmapped
// while the drop-down is in or on another output: 0 frames (Ma). Rule 4: tokens only, no look's name.
PanelWindow {
    id: dd
    required property var screen

    Watch { doc: "mod.terminal" }
    Watch { doc: "runtime.layout"; active: dd.want || dd.shown }

    readonly property var d: Store.docs["mod.terminal"] || ({})
    readonly property var s: d.settings || ({})
    readonly property string outName: screen ? screen.name : ""
    readonly property bool firstHere: Quickshell.screens.length > 0 && Quickshell.screens[0].name === outName
    readonly property var drop: d.dropdown || ({})
    readonly property bool want: drop.open === true && (drop.output !== undefined ? drop.output === outName : firstHere)
    readonly property real scrW: screen ? screen.width : 1920
    readonly property real scrH: screen ? screen.height : 1080

    // ---- where: the main bar, an edge, the centre, a position ----
    readonly property var lay: ShellLayout.of(outName)
    function edgeLay(e) { return (lay && lay.edges && lay.edges[e]) || {} }
    function band(e) { var f = lay ? lay.frame : null; return f && f.on && f.band ? (f.band[e] || 0) : 0 }
    function barOn(e) { var ed = edgeLay(e); return ed.bar === true && ed.visibility !== "hidden" }
    // How far the free area stands off edge `e`: the frame's band and a bar shown there (framegeom.js holeSide).
    function hole(e) { return band(e) + (barOn(e) ? Math.max(0, edgeLay(e).inset || 0) + Theme.barH : 0) }
    // The main bar: the top bar on this output, else the bottom one; a side bar is not one (docs/ux/terminal.md).
    readonly property string mainBar: barOn("top") ? "top" : (barOn("bottom") ? "bottom" : "")
    readonly property string placeSet: String(s.place || "bar")
    // `bar` without a horizontal bar here stands at the top edge (Settings says why: `noBar`).
    readonly property bool noBar: placeSet === "bar" && mainBar === ""
    readonly property string mode: noBar ? "edge" : placeSet
    readonly property string edge: mode === "bar" ? mainBar : (noBar ? "top" : String(s.edge || "top"))
    readonly property bool attached: mode === "bar" || mode === "edge"
    readonly property bool sideways: attached && (edge === "left" || edge === "right")
    // A sheet hangs from what stands on its edge: a bar or the frame's band draws the join; a bare screen edge does not.
    readonly property bool joins: attached && Theme.surfaceJoin && hole(edge) > 0
    readonly property real heightPct: {
        var sz = s.sizes || {}
        return (sz[outName] !== undefined ? sz[outName] : (s.height || 45)) / 100
    }
    // The sheet's box (logical px): across its edge × out of it.
    readonly property real sheetW: Math.round(sideways ? scrW * heightPct
        : scrW * (mode === "edge" ? (s.length || 100) : (s.width || 60)) / 100 - (mode === "edge" && (s.length || 100) >= 100 ? hole("left") + hole("right") : 0))
    readonly property real sheetH: Math.round(sideways ? scrH * (s.length || 100) / 100 - (((s.length || 100) >= 100) ? hole("top") + hole("bottom") : 0)
        : scrH * heightPct)
    // The fillets' room round a joined sheet.
    readonly property real pad: joins ? Theme.rJoin : 0
    // The window: the sheet plus its fillets, placed against its edge or floating.
    readonly property real winW: sheetW + (joins && !sideways ? 2 * pad : 0)
    readonly property real winH: sheetH + (joins && sideways ? 2 * pad : 0)
    readonly property var anchorXY: {
        var a = String(s.anchor || "top-left"), x = 0, y = 0
        var left = hole("left"), right = hole("right"), top = hole("top"), bottom = hole("bottom")
        if (a.indexOf("left") >= 0) x = left + Theme.gap
        else if (a.indexOf("right") >= 0) x = scrW - right - Theme.gap - winW
        else x = (scrW - winW) / 2
        if (a.indexOf("top") >= 0) y = top + Theme.gap
        else if (a.indexOf("bottom") >= 0) y = scrH - bottom - Theme.gap - winH
        else y = (scrH - winH) / 2
        return { x: x + (s.offset_x || 0), y: y + (s.offset_y || 0) }
    }
    readonly property real winX: Math.round(mode === "position" ? anchorXY.x
        : mode === "center" ? (scrW - winW) / 2
        : edge === "left" ? hole("left") : edge === "right" ? scrW - hole("right") - winW
        : (scrW - winW) / 2)
    readonly property real winY: Math.round(mode === "position" ? anchorXY.y
        : mode === "center" ? (scrH - winH) / 2
        : edge === "top" ? hole("top") : edge === "bottom" ? scrH - hole("bottom") - winH
        : (scrH - winH) / 2)

    screen: dd.screen
    anchors.top: true
    anchors.left: true
    margins.top: winY
    margins.left: winX
    implicitWidth: Math.max(1, winW)
    implicitHeight: Math.max(1, winH)
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "kurashi-terminal-dropdown"
    // (the keyboard is the host's window's, over the well; the sheet's keys take it on a click)
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // ---- motion: out of the bar or the edge it hangs from; a calm fade and scale when it floats; a cut when motion is off ----
    readonly property bool still: Theme.motionKind === "none"
    property real out: 0                  // 0 in, 1 out
    readonly property bool shown: out > 0 || want
    visible: shown
    onWantChanged: {
        if (want) { reported = false; outAnim.to = 1 } else { withdraw(); outAnim.to = 0 }
        if (still) { out = outAnim.to; settle() } else outAnim.restart()
    }
    NumberAnimation {
        id: outAnim
        target: dd
        property: "out"
        duration: Theme.stdMs
        easing.type: Easing.BezierSpline
        easing.bezierCurve: dd.want ? Theme.enterCurve : Theme.continuousCurve
        onRunningChanged: if (!running) dd.settle()
    }
    // A move of the sheet (the place, the size, another output) is a move: the well's report is taken again at rest.
    onWinXChanged: replace()
    onWinYChanged: replace()
    onWinWChanged: replace()
    onWinHChanged: replace()
    function replace() { if (want && out >= 1) Qt.callLater(report) }

    property bool reported: false
    function settle() { if (want && out >= 1) report() }
    function report() {
        if (!want || !well.width) return
        var p = well.mapToItem(root, 0, 0)
        Store.act("terminal.place", { where: "dropdown", on: true, output: outName,
            x: Math.round(winX + p.x), y: Math.round(winY + p.y),
            width: Math.round(well.width), height: Math.round(well.height), fresh: !reported })
        reported = true
    }
    function withdraw() { Store.act("terminal.place", { where: "dropdown", on: false }) }

    Item {
        id: root
        anchors.fill: parent
        clip: dd.attached
        // The slide: the sheet starts behind its edge and comes out of it.
        readonly property real travel: dd.sideways ? dd.winW : dd.winH
        readonly property real shift: dd.attached && !dd.still ? (1 - dd.out) * travel : 0
        Item {
            id: sheet
            width: dd.winW
            height: dd.winH
            x: dd.attached && dd.edge === "left" ? -root.shift : dd.attached && dd.edge === "right" ? root.shift : 0
            y: dd.attached && dd.edge === "top" ? -root.shift : dd.attached && dd.edge === "bottom" ? root.shift : 0
            opacity: dd.attached ? 1 : dd.out
            scale: dd.attached ? 1 : 0.96 + 0.04 * dd.out

            // Joined to its bar or band: one sheet with it (the launcher's and the bar cards' join).
            JoinedCard {
                visible: dd.joins
                x: dd.sideways && dd.edge === "right" ? 0 : (dd.sideways ? -dd.pad : 0)
                y: dd.sideways ? 0 : (dd.edge === "top" ? -dd.pad : 0)
                width: dd.sideways ? dd.winW + dd.pad : dd.winW
                height: dd.sideways ? dd.winH : dd.winH + dd.pad
                pad: dd.pad
                edge: dd.edge
            }
            // Floating, or on a bare edge: the look's card.
            Block {
                visible: !dd.joins
                anchors.fill: parent
                radius: Theme.rLg
                fill: Theme.panel
                flatBorder: Theme.surfaceHair
                penSeed: 0x7E83
            }

            // The card's box inside the fillets.
            Item {
                id: box
                x: dd.joins && !dd.sideways ? dd.pad : 0
                y: dd.joins && dd.sideways ? dd.pad : 0
                width: dd.sheetW
                height: dd.sheetH

                // The tab row on the free side (away from the edge it hangs from; at the bottom when it floats).
                readonly property bool rowTop: dd.attached && dd.edge === "bottom"
                TabRow {
                    id: row
                    x: Theme.pad
                    width: parent.width - 2 * Theme.pad
                    y: box.rowTop ? grip.height + Theme.xs : parent.height - height - Theme.xs - grip.height
                    doc: dd.d
                    output: dd.outName
                }
                Rectangle {
                    id: well
                    x: Theme.pad
                    y: box.rowTop ? row.y + row.height + Theme.xs : Theme.pad
                    width: parent.width - 2 * Theme.pad
                    height: Math.max(1, parent.height - row.height - grip.height - Theme.pad - 2 * Theme.xs - (box.rowTop ? 0 : Theme.xs))
                    radius: Theme.rSm
                    // The terminal's own ground over the sheet's material (`opacity`; 0: the material alone).
                    color: Qt.alpha(Theme.surface, Math.max(0, Math.min(100, Number(dd.s.opacity !== undefined ? dd.s.opacity : 60))) / 100)
                    Notice {
                        anchors.fill: parent
                        doc: dd.d
                        place: "dropdown"
                    }
                }
                // The grip: the free edge, dragged for this output's height (`terminal.resize`).
                Grip {
                    id: grip
                    width: parent.width
                    y: box.rowTop ? 0 : parent.height - height
                    visible: dd.attached && !dd.sideways
                    height: visible ? 8 : 0
                    fromTop: box.rowTop
                    screenH: dd.scrH
                    startPct: dd.heightPct
                    output: dd.outName
                    forced: !!(dd.d.forced && dd.d.forced.sizes)
                }
            }
        }
    }
}
