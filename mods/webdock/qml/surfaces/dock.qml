import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import "../"

// The web dock's edge window on one output (MODS.md "Web dock", "Shell side"; K40; K19). Per output it is the only window
// the dock costs before a reveal: 4 px thick along the whole edge, transparent, with the 2 px hover zone and the indicator and
// nothing else (no strip, card or loaders). The strip and the card are one window for the whole shell (DockWindow.qml): the
// window on the first screen makes it on the first reveal, keeps it afterwards, and retargets it to the output the dock is on.
// shell.qml creates one of these per output, with `screen` set.
PanelWindow {
    id: edgeWin

    Watch { doc: "mod.webdock" }

    readonly property var d: Store.docs["mod.webdock"] || ({})
    readonly property string outName: screen ? screen.name : ""
    readonly property string edge: d.edge || "right"
    readonly property bool sideways: edge === "left" || edge === "right"
    readonly property real along: sideways ? height : width      // the window's length along its edge: the usable area
    readonly property int restT: 4
    readonly property string mode: d.mode || "hidden"
    readonly property bool firstHere: Quickshell.screens.length > 0 && Quickshell.screens[0].name === outName
    // The dock is on this output: its document names it, or the first output while it names none.
    readonly property bool dockHere: mode !== "hidden" && (d.output !== undefined ? d.output === outName : firstHere)
    readonly property bool indicatorOn: d.indicator !== false

    // The one dock window: owned by the first screen's instance, made on the first reveal and kept (no destroy per reveal).
    readonly property bool anyOpen: mode !== "hidden"
    property bool everOpened: false
    onAnyOpenChanged: if (anyOpen) everOpened = true
    Component.onCompleted: if (anyOpen) everOpened = true
    readonly property string targetName: d.output !== undefined ? d.output : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
    readonly property var target: screenNamed(targetName)

    function screenNamed(name) {
        var all = Quickshell.screens
        for (var i = 0; i < all.length; i++)
            if (all[i].name === name) return all[i]
        return all.length > 0 ? all[0] : null
    }
    // The edge of this output borders another output (the daemon waits longer on a shared edge).
    function sharedEdge() {
        var list = Quickshell.screens
        for (var i = 0; i < list.length; i++) {
            var o = list[i]
            if (!screen || o.name === outName) continue
            if (typeof o.x !== "number" || typeof screen.x !== "number") continue
            var vertical = screen.y < o.y + o.height && o.y < screen.y + screen.height
            var horizontal = screen.x < o.x + o.width && o.x < screen.x + screen.width
            if (edge === "right" && o.x === screen.x + screen.width && vertical) return true
            if (edge === "left" && o.x + o.width === screen.x && vertical) return true
            if (edge === "top" && o.y + o.height === screen.y && horizontal) return true
            if (edge === "bottom" && o.y === screen.y + screen.height && horizontal) return true
        }
        return false
    }

    implicitWidth: sideways ? restT : 0
    implicitHeight: sideways ? 0 : restT
    anchors.top: edge !== "bottom"
    anchors.bottom: edge !== "top"
    anchors.left: edge !== "right"
    anchors.right: edge !== "left"
    color: "transparent"
    // Normal placement with no zone of its own: the window sits in the usable area (under a top bar, say).
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "kurashi-webdock-edge"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: zoneRegion

    Region {
        id: zoneRegion
        x: edgeWin.sideways ? (edgeWin.edge === "right" ? edgeWin.width - 2 : 0) : 0
        y: edgeWin.sideways ? 0 : (edgeWin.edge === "bottom" ? edgeWin.height - 2 : 0)
        width: edgeWin.sideways ? 2 : edgeWin.width
        height: edgeWin.sideways ? edgeWin.height : 2
    }
    // The hover zone: 2 px along the whole edge, reported while the pointer is on it.
    Box {
        id: zone
        edge: edgeWin.edge
        surfW: edgeWin.width
        surfH: edgeWin.height
        a0: 0
        a1: 2
        l0: 0
        l1: edgeWin.along
        HoverHandler { id: zoneHover }
    }
    // The indicator: a 4 x 48 px pill centred on the edge, while the dock is not on this output (off by setting).
    Box {
        id: pill
        visible: !edgeWin.dockHere && edgeWin.indicatorOn
        edge: edgeWin.edge
        surfW: edgeWin.width
        surfH: edgeWin.height
        a0: 0
        a1: 4
        l0: (edgeWin.along - 48) / 2
        l1: (edgeWin.along + 48) / 2
        Rectangle {
            anchors.fill: parent
            radius: 2
            color: Theme.outline
            opacity: 0.5
        }
    }

    // `webdock.hover {part: edge, inside, output, shared?}`: on change only.
    readonly property bool edgeIn: zoneHover.hovered
    onEdgeInChanged: {
        var args = { part: "edge", inside: edgeIn, output: outName }
        if (sharedEdge()) args.shared = true
        Store.act("webdock.hover", args)
    }

    Component {
        id: dockWinC
        DockWindow { targetScreen: edgeWin.target }
    }
    Loader {
        id: dockWin
        active: edgeWin.firstHere && edgeWin.everOpened
        sourceComponent: dockWinC
    }
}
