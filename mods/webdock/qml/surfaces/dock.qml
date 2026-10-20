import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.components
import "../"

// The web dock's edge surface on one output (MODS.md "Web dock", "Shell side"; K40; docs/ux/webdock.md). The daemon owns
// every mode: this draws `mod.webdock` and sends `webdock.*` intents, nothing else. Hidden, the surface is 4 px wide along
// its edge: the 2 px hover zone and the indicator, no frames. Open, it holds the strip (a Box on the edge) and, when a card
// or a side panel is up, that beside the strip. Its thickness is what it draws plus the grace, and its input region (the
// mask) covers exactly those parts, so the rest of the edge passes clicks through. The web host's card sits at the same
// place (WebCard: margin = the strip), so the two line up. shell.qml creates one per output with `screen` set.
PanelWindow {
    id: dock

    Watch { doc: "mod.webdock" }

    // ---- the document, the output and the mode ----
    readonly property var d: Store.docs["mod.webdock"] || ({})
    readonly property bool hasDoc: Store.docs["mod.webdock"] !== undefined
    readonly property string outName: screen ? screen.name : ""
    readonly property real outW: screen ? screen.width : 1920
    readonly property real outH: screen ? screen.height : 1080
    readonly property string edge: d.edge || "right"
    readonly property bool sideways: edge === "left" || edge === "right"
    // The surface's length along its edge: the usable area (below a top bar's exclusive zone, say), not the output.
    readonly property real along: sideways ? height : width
    // One dock at a time: the output the document names, or the first output while it names none.
    readonly property bool mine: d.output !== undefined ? d.output === outName
        : (Quickshell.screens.length > 0 && Quickshell.screens[0].name === outName)
    readonly property string mode: hasDoc ? (d.mode || "hidden") : "hidden"
    readonly property bool open: mode !== "hidden" && mine
    readonly property bool extended: open && mode === "extended"
    readonly property bool reduced: Theme.tok("motion.profile", "calm") === "none"
    readonly property var geo: d.geometry || ({})
    readonly property int stripPx: geo.strip || 56
    readonly property int grace: geo.grace !== undefined ? geo.grace : 24
    readonly property int phoneW: geo.width || 412
    readonly property int largePct: geo.large || 90
    readonly property bool large: d.size === "large"
    readonly property bool pinned: d.pinned === true
    readonly property bool reserve: d.reserve === true
    readonly property bool indicatorOn: d.indicator !== false
    readonly property bool wantFocus: d.engaged === true && open

    // ---- the pins and the card's subject ----
    readonly property var pins: d.pins || []
    readonly property string shownId: d.shown || ""
    readonly property var shownPin: pinOf(shownId)
    readonly property string hostState: (d.host && d.host.state) || "off"
    readonly property string hostReason: (d.host && d.host.reason) || ""
    readonly property var view: viewOf(shownPin && shownPin.kind === "view" ? String(shownPin.target) : "")
    property var rowList: []
    onPinsChanged: refreshRows()

    function pinOf(id) {
        for (var i = 0; i < pins.length; i++)
            if (pins[i].id === id) return pins[i]
        return null
    }
    function indexOfPin(id) {
        for (var i = 0; i < pins.length; i++)
            if (pins[i].id === id) return i
        return -1
    }
    // `mod:<id>:<panel>` as { mod, panel }; null for anything else (the same rule as frontend/core/mods.js panelOf).
    function viewOf(target) {
        var s = String(target || "")
        if (s.indexOf("mod:") !== 0) return null
        var rest = s.substring(4)
        var c = rest.indexOf(":")
        if (c <= 0 || c === rest.length - 1) return null
        return { mod: rest.substring(0, c), panel: rest.substring(c + 1) }
    }
    // The strip's rows: the pins in order with a divider where the kind changes, then the dock's controls. The list is
    // replaced only when its content changes, so the strip's tiles (and the focus on them) survive other patches.
    function refreshRows() {
        var out = []
        for (var i = 0; i < pins.length; i++) {
            if (i > 0 && pins[i].kind !== pins[i - 1].kind) out.push({ kind: "divider" })
            out.push({ kind: "pin", pin: pins[i] })
        }
        if (pins.length > 0) out.push({ kind: "divider" })
        out.push({ kind: "ctl", ctl: "pin" }, { kind: "ctl", ctl: "add" }, { kind: "ctl", ctl: "settings" })
        if (JSON.stringify(out) !== JSON.stringify(rowList)) rowList = out
    }
    Component.onCompleted: refreshRows()

    // ---- what the panel beside the strip shows ----
    readonly property bool viewCard: extended && view !== null
    readonly property bool coldCard: extended && shownPin !== null && shownPin.kind === "web" && hostState !== "ready"
    readonly property bool emptyCard: extended && pins.length === 0
    // The add form and a pin's menu take the card's place beside the strip, whatever the card shows.
    property string side: ""         // "" | "add" | "menu"
    property string menuId: ""
    // The tile that opened the side panel: when the panel closes, the keyboard goes back to it.
    property string sideOwner: ""
    onSideChanged: if (side === "" && open && sideOwner !== "") Qt.callLater(function () { stripItem.focusId(dock.sideOwner) })
    readonly property bool sideUp: open && side !== ""
    readonly property bool cardUp: open && !sideUp && (viewCard || coldCard || emptyCard)
    readonly property bool panelUp: sideUp || cardUp
    readonly property string kindNow: sideUp ? "side-" + side : cardUp ? (viewCard ? "view" : (coldCard ? "cold" : "empty")) : ""
    // The content held while a panel slides out (it stays until the slide ends, then unloads: Ma).
    property string held: ""
    onKindNowChanged: if (kindNow !== "") held = kindNow
    onOpenChanged: if (!open) side = ""
    readonly property string kind: open ? kindNow : held

    // ---- geometry: WebCard's sizes (phone, large) and the strip's centred span ----
    readonly property real gap: Theme.gap
    readonly property real cardW: large ? Math.round(outW * largePct / 100) : phoneW
    // WebCard's sizes: a side edge is limited by the surface's own length; a top or bottom edge by the output's height.
    readonly property real cardH: sideways
        ? (large ? Math.round(along - 2 * gap) : Math.min(2 * phoneW, Math.round(along - 2 * gap)))
        : (large ? Math.round(outH - 2 * gap) : Math.min(2 * phoneW, Math.round(outH - 2 * gap)))
    readonly property real sideSize: 300
    readonly property bool kindSide: kind.indexOf("side") === 0
    // A panel across its edge (its thickness) and along it.
    readonly property real panelAcross: kind === "" ? 0 : (kindSide ? sideSize : (sideways ? cardW : cardH))
    readonly property real panelAlong: kind === "" ? 0 : (kindSide ? sideSize : (sideways ? cardH : cardW))
    readonly property real panelAlong0: (along - panelAlong) / 2
    readonly property real stripAlong0: (along - stripLen) / 2
    readonly property real stripMax: along - 2 * gap
    readonly property real stripLen: Math.min(stripItem.contentLen, stripMax)
    readonly property real restT: 4
    // The strip and the card slide in and out: the strip 180 ms, the card 40 ms later (Theme standard); reduced motion
    // (profile none) fades instead of sliding. The surface keeps its size until both have finished.
    property real reveal: open ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: dock.reduced ? Theme.quickMs : 180; easing.type: Easing.OutCubic } }
    property real cardReveal: panelUp ? 1 : 0
    Behavior on cardReveal {
        SequentialAnimation {
            PauseAnimation { duration: dock.reduced ? 0 : 40 }
            NumberAnimation { duration: dock.reduced ? Theme.quickMs : 180; easing.type: Easing.OutCubic }
        }
    }
    readonly property bool surfaceUp: open || reveal > 0.001 || cardReveal > 0.001
    // Across the edge: the strip, its grace, and the panel (only while open or while it slides out).
    readonly property real thick: surfaceUp ? stripPx + grace + panelAcross : restT
    readonly property real loAlong: Math.max(0, (panelUp ? Math.min(stripAlong0, panelAlong0) : stripAlong0) - grace)
    readonly property real hiAlong: Math.min(along, (panelUp ? Math.max(stripAlong0 + stripLen, panelAlong0 + panelAlong)
        : stripAlong0 + stripLen) + grace)

    // ---- the window ----
    implicitWidth: sideways ? thick : 0
    implicitHeight: sideways ? 0 : thick
    anchors.top: edge !== "bottom"
    anchors.bottom: edge !== "top"
    anchors.left: edge !== "right"
    anchors.right: edge !== "left"
    color: "transparent"
    exclusionMode: reserve && pinned && open ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: stripPx
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "kurashi-webdock-shell"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: open ? activeRegion : zoneRegion

    Region {
        id: zoneRegion
        x: dock.sideways ? (dock.edge === "right" ? dock.width - 2 : 0) : 0
        y: dock.sideways ? 0 : (dock.edge === "bottom" ? dock.height - 2 : 0)
        width: dock.sideways ? 2 : dock.width
        height: dock.sideways ? dock.height : 2
    }
    Region {
        id: activeRegion
        x: dock.sideways ? (dock.edge === "right" ? dock.width - dock.thick : 0) : dock.loAlong
        y: dock.sideways ? dock.loAlong : (dock.edge === "bottom" ? dock.height - dock.thick : 0)
        width: dock.sideways ? dock.thick : dock.hiAlong - dock.loAlong
        height: dock.sideways ? dock.hiAlong - dock.loAlong : dock.thick
    }

    // ---- intents ----
    function send(action, args) { Store.act(action, args || ({})) }

    // Engaged: the dock has keyboard focus (a part took it). Sent on change only.
    property bool sentEngaged: false
    function engage(on) {
        if (on === sentEngaged) return
        sentEngaged = on
        send("webdock.engage", { on: on })
    }
    // Hover parts: the pointer entered or left a part (its grace included). Sent on change only; `shared` on an edge
    // another output touches (the daemon waits longer there).
    property var sentHover: ({ edge: false, strip: false, card: false })
    function hover(part, inside) {
        if (sentHover[part] === inside) return
        sentHover[part] = inside
        var args = { part: part, inside: inside, output: outName }
        if (part === "edge" && sharedEdge()) args.shared = true
        send("webdock.hover", args)
    }
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

    // Keyboard: the front part takes focus when the daemon says `engaged` (a toggle), the card when extended, else the strip.
    onWantFocusChanged: if (wantFocus) Qt.callLater(focusFront)
    function focusFront() {
        if (panelUp && panelLoader.item) panelLoader.item.forceActiveFocus()
        else stripItem.focusFirst()
    }

    FocusScope {
        id: scope
        anchors.fill: parent
        onActiveFocusChanged: dock.engage(scope.activeFocus)

        // The hover zone: 2 px along the whole edge. It counts only while the dock is hidden (the strip covers it when open).
        Box {
            id: zone
            edge: dock.edge
            surfW: dock.width
            surfH: dock.height
            a0: 0
            a1: 2
            l0: 0
            l1: dock.along
            HoverHandler { id: zoneHover }
        }
        // The indicator: a 4 x 48 px pill centred on the edge, while hidden (off by setting; hover still works).
        Box {
            id: pill
            visible: !dock.open && dock.indicatorOn
            edge: dock.edge
            surfW: dock.width
            surfH: dock.height
            a0: 0
            a1: 4
            l0: (dock.along - 48) / 2
            l1: (dock.along + 48) / 2
            Rectangle {
                anchors.fill: parent
                radius: 2
                color: Theme.outline
                opacity: 0.5
            }
        }
        // The strip: slides in from the edge (reduced motion: fades).
        Box {
            id: stripBox
            edge: dock.edge
            surfW: dock.width
            surfH: dock.height
            a0: (dock.reduced ? 0 : dock.reveal - 1) * dock.stripPx
            a1: a0 + dock.stripPx
            l0: dock.stripAlong0
            l1: dock.stripAlong0 + dock.stripLen
            visible: dock.reveal > 0.001
            opacity: dock.reduced ? dock.reveal : 1
            HoverHandler { id: stripHover }

            Strip {
                id: stripItem
                anchors.fill: parent
                vertical: dock.sideways
                thick: dock.stripPx
                rows: dock.rowList
                shownId: dock.shownId
                pinned: dock.pinned
                pinForced: false
                onPinSelected: id => dock.send("webdock.select", { pin: id, output: dock.outName })
                onPinMenu: id => { dock.menuId = id; dock.sideOwner = id; dock.side = "menu" }
                onPinToggled: dock.send("webdock.pin", { on: !dock.pinned })
                onAddPressed: { dock.sideOwner = "add"; dock.side = "add" }
                onSettingsPressed: dock.send("settings.open", { key: "mods.webdock.pins" })
                onBackPressed: dock.send("webdock.back", {})
                onTabPressed: if (dock.panelUp && panelLoader.item) panelLoader.item.forceActiveFocus()
            }
        }
        // The card or the side panel, beside the strip: it slides 40 ms after the strip.
        Box {
            id: panelBox
            edge: dock.edge
            surfW: dock.width
            surfH: dock.height
            a0: dock.stripPx + (dock.reduced ? 0 : (dock.cardReveal - 1) * dock.panelAcross)
            a1: a0 + dock.panelAcross
            l0: dock.panelAlong0
            l1: dock.panelAlong0 + dock.panelAlong
            visible: dock.cardReveal > 0.001
            opacity: dock.reduced ? dock.cardReveal : 1
            HoverHandler { id: panelHover }

            Loader {
                id: panelLoader
                anchors.fill: parent
                active: dock.kind !== "" && dock.cardReveal > 0.001
                sourceComponent: dock.kind === "side-menu" ? menuC : (dock.kind === "side-add" ? addC
                    : (dock.kind === "view" ? viewC : (dock.kind === "cold" ? coldC : emptyC)))
            }
        }
    }

    // The hover parts report what they show (never a part that is hidden): the zone while hidden, the strip and the panel
    // while open.
    readonly property bool edgeIn: zoneHover.hovered && !open
    readonly property bool stripIn: stripHover.hovered && open
    readonly property bool cardIn: panelHover.hovered && panelUp
    onEdgeInChanged: hover("edge", edgeIn)
    onStripInChanged: hover("strip", stripIn)
    onCardInChanged: hover("card", cardIn)

    // ---- the panels' content ----
    Component {
        id: viewC
        Card {
            anchors.fill: parent
            title: dock.shownPin ? String(dock.shownPin.title || "") : ""
            large: dock.large
            onSizeChosen: size => dock.send("webdock.size", { size: size })
            onCollapse: dock.send("webdock.collapse", {})
            onEscaped: dock.send("webdock.back", {})
            ModLoader {
                id: viewBody
                anchors.fill: parent
                provide: dock.view ? "panel:" + dock.view.panel : ""
                mod: dock.view ? dock.view.mod : ""
                shown: true
            }
            // The view's mod is off (or its panel is gone): said in words, the card stays (view pins still work).
            Notice {
                anchors.fill: parent
                visible: viewBody.item === null
                text: I18n.tr("webdock.view.gone")
            }
        }
    }
    Component {
        id: coldC
        Card {
            anchors.fill: parent
            title: dock.shownPin ? String(dock.shownPin.title || "") : ""
            large: dock.large
            onSizeChosen: size => dock.send("webdock.size", { size: size })
            onCollapse: dock.send("webdock.collapse", {})
            onEscaped: dock.send("webdock.back", {})
            Notice {
                anchors.fill: parent
                text: dock.hostState === "missing" ? I18n.tr("webdock.host.missing")
                    : (dock.hostState === "failed" ? I18n.tr(dock.hostReason || "webdock.dock.host.failed")
                        : I18n.tr("webdock.host.starting"))
            }
        }
    }
    Component {
        id: emptyC
        Card {
            anchors.fill: parent
            title: I18n.tr("webdock.dock.name")
            sizable: false
            onCollapse: dock.send("webdock.collapse", {})
            onEscaped: dock.send("webdock.back", {})
            Notice {
                anchors.fill: parent
                text: I18n.tr("webdock.empty")
                actionLabel: I18n.tr("webdock.dock.empty.add")
                onActionPressed: { dock.sideOwner = "add"; dock.side = "add" }
            }
        }
    }
    Component {
        id: addC
        AddForm {
            anchors.fill: parent
            onAdded: dock.side = ""
            onCancelled: dock.side = ""
        }
    }
    Component {
        id: menuC
        PinMenu {
            anchors.fill: parent
            pin: dock.pinOf(dock.menuId) || ({})
            index: dock.indexOfPin(dock.menuId)
            count: dock.pins.length
            onMoved: to => { dock.send("webdock.move", { pin: dock.menuId, to: to }); dock.side = "" }
            onRemoved: { dock.send("webdock.remove", { pin: dock.menuId }); dock.side = "" }
            onClosed: dock.side = ""
        }
    }
}
