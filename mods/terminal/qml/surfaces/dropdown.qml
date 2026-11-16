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
    // Out without a named output (the niri bind sends none): on the focused output (the output whose workspaces hold
    // the focused one, as shell.qml picks the Stage's), latched while it is out.
    Watch { doc: "svc.workspaces" }
    function focusedHere() {
        var o = (Store.docs["svc.workspaces"] && Store.docs["svc.workspaces"].outputs) || {}
        var any = false
        for (var n in o) {
            var l = o[n] || []
            for (var j = 0; j < l.length; j++) if (l[j].focused) { any = true; if (n === outName) return true }
        }
        return !any && firstHere
    }
    readonly property bool openNow: drop.open === true
    property bool latched: false
    onOpenNowChanged: latched = openNow && focusedHere()
    readonly property bool want: openNow && (drop.output !== undefined ? drop.output === outName : latched)
    // (made while it is out — a reload, a new output: it takes its place at once, without the slide)
    Component.onCompleted: {
        latched = openNow && focusedHere()
        if (want) { out = 1; Qt.callLater(settle) }
    }
    readonly property real scrW: screen ? screen.width : 1920
    readonly property real scrH: screen ? screen.height : 1080

    // ---- where: the main bar, an edge, the centre, a position (SheetGeom, shared with the shell's own sheets) ----
    readonly property real heightPct: {
        var sz = s.sizes || {}
        return (sz[outName] !== undefined ? sz[outName] : (s.height || 45)) / 100
    }
    SheetGeom {
        id: sg
        outName: dd.outName
        scrW: dd.scrW
        scrH: dd.scrH
        place: String(dd.s.place || "bar")
        edgeSet: String(dd.s.edge || "top")
        widthPct: dd.s.width || 60
        lengthPct: dd.s.length || 100
        heightFrac: dd.heightPct
        anchor: String(dd.s.anchor || "top-left")
        offsetX: dd.s.offset_x || 0
        offsetY: dd.s.offset_y || 0
    }
    readonly property bool noBar: sg.noBar
    readonly property string edge: sg.edge
    readonly property bool attached: sg.attached
    readonly property bool sideways: sg.sideways
    readonly property bool joins: sg.joins
    readonly property real winX: sg.winX
    readonly property real winY: sg.winY
    readonly property real winW: sg.winW
    readonly property real winH: sg.winH

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
    // (the keyboard is the host's window's, over the well; the sheet takes it only while a tab's name is edited)
    WlrLayershell.keyboardFocus: row.editing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // A click elsewhere on this output while the terminal holds the keyboard (exclusively, so a click — not a focus
    // change — is what "elsewhere" means): `hide_on_blur` hides it unless kept open; otherwise it gives the keyboard back
    // and stays out. The click is spent on that (the next one reaches the window under it).
    readonly property bool awayOn: want && out >= 1 && d.keys === true
    PanelWindow {
        id: away
        screen: dd.screen
        visible: dd.awayOn
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "kurashi-terminal-away"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: Store.act("terminal.blur", {})
        }
    }

    // ---- motion: out of the bar or the edge it hangs from; a calm fade and scale when it floats; a cut when motion is off ----
    readonly property bool still: Theme.motionKind === "none"
    property real out: 0                  // 0 in, 1 out
    readonly property bool shown: out > 0 || want
    visible: shown
    onWantChanged: {
        if (want) { reported = false; outAnim.to = 1 } else { withdraw(); outAnim.to = 0 }
        leaveLater.stop()
        if (still) { out = outAnim.to; settle() }
        // Leaving with the text's still on screen: two frames at rest first, while the host's window goes from over it
        // (the same pixels; else a frame with neither between the host's unmap and the still's first frame).
        else if (!want && lastFrame.status === Image.Ready && lastFrame.there) leaveLater.start()
        else outAnim.restart()
    }
    Timer {
        id: leaveLater
        interval: 34
        onTriggered: outAnim.restart()
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

    SheetFrame {
        id: root
        anchors.fill: parent
        geom: sg
        out: dd.out
        still: dd.still
        // The tab row on the free side (away from the edge it hangs from; at the bottom when it floats).
        TabRow {
            id: row
            x: Theme.pad
            width: parent.width - 2 * Theme.pad
            y: root.freeTop ? grip.height + Theme.xs : parent.height - height - Theme.xs - grip.height
            doc: dd.d
            output: dd.outName
            showPin: true
        }
        // A refused folder, said over the tab row (never under the terminal's text; the well keeps its size).
        NoticeStrip {
            x: row.x
            y: row.y
            width: row.width
            height: row.keyH
            doc: dd.d
            owner: dd.want && dd.d.shown_in === "dropdown"
        }
        Rectangle {
            id: well
            x: Theme.pad
            y: root.freeTop ? row.y + row.height + Theme.xs : Theme.pad
            width: parent.width - 2 * Theme.pad
            height: Math.max(1, parent.height - row.height - grip.height - Theme.pad - 2 * Theme.xs - (root.freeTop ? 0 : Theme.xs))
            radius: Theme.rSm
            // The terminal's own ground over the sheet's material (`opacity`; 0: the material alone).
            color: Qt.alpha(Theme.surface, Math.max(0, Math.min(100, Number(dd.s.opacity !== undefined ? dd.s.opacity : 60))) / 100)
            Notice {
                anchors.fill: parent
                doc: dd.d
                place: "dropdown"
            }
            // The text's last frame while the sheet moves and until the host's window is over the well.
            Still {
                id: lastFrame
                anchors.fill: parent
                doc: dd.d
                place: "dropdown"
                keep: dd.want && dd.out >= 1
                hold: dd.shown && (!dd.want || (dd.d.shown_in === "dropdown"
                    && !(dd.out >= 1 && dd.d.host && dd.d.host.shows === "dropdown")))
            }
            onWidthChanged: dd.replace()
            onHeightChanged: dd.replace()
        }
        // The grip: the free edge, dragged for this output's height (`terminal.resize`).
        Grip {
            id: grip
            width: parent.width
            y: root.freeTop ? 0 : parent.height - height
            visible: dd.attached && !dd.sideways
            height: visible ? 8 : 0
            fromTop: root.freeTop
            screenH: dd.scrH
            startPct: dd.heightPct
            output: dd.outName
            forced: !!(dd.d.forced && dd.d.forced.sizes)
        }
    }
}
