import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.components
import qs.components.motion

// The web dock's window: the strip, the view card, the cold or empty card, the add form and a pin's menu. There is one of
// these for the whole shell (K19: a window costs once): the edge window on the first screen makes it on the first reveal,
// keeps it afterwards, and retargets it to the output the dock is on (`targetScreen`, the way Stage follows the focused
// output). While the dock is hidden it is transparent, input-less (an empty mask) and draws nothing: 0 frames. The daemon
// owns every mode (K40); this draws `mod.webdock` and sends `webdock.*` intents. The card and the strip centre in the
// window's own height, which is the usable area (under a top bar, say).
PanelWindow {
    id: dock

    property var targetScreen: null
    screen: targetScreen

    Watch { doc: "mod.webdock" }

    // ---- the document, the output and the mode ----
    readonly property var d: Store.docs["mod.webdock"] || ({})
    readonly property bool hasDoc: Store.docs["mod.webdock"] !== undefined
    readonly property string outName: screen ? screen.name : ""
    readonly property real outW: screen ? screen.width : 1920
    readonly property real outH: screen ? screen.height : 1080
    readonly property string edge: d.edge || "right"
    readonly property bool sideways: edge === "left" || edge === "right"
    readonly property real along: sideways ? height : width      // the window's length along its edge
    readonly property bool mine: d.output !== undefined ? d.output === outName
        : (Quickshell.screens.length > 0 && Quickshell.screens[0].name === outName)
    readonly property string mode: hasDoc ? (d.mode || "hidden") : "hidden"
    readonly property bool open: mode !== "hidden" && mine
    readonly property bool extended: open && mode === "extended"
    // (motion off, or reduce motion's own profile: K83 D1, every surface fades)
    readonly property bool reduced: Theme.tok("motion.profile", "calm") === "none" || Theme.tok("motion.profile", "") === "reduced"
    // Reduced motion fades (docs/ux/webdock.md "Motion": fade only), over a fixed short time: `motion.quick_ms` is 0
    // under profile none, and a zero-length fade is a cut (I99).
    readonly property int fadeMs: 120
    readonly property var geo: d.geometry || ({})
    readonly property int stripPx: geo.strip || 56
    readonly property int grace: geo.grace !== undefined ? geo.grace : 24
    // W76: the card's box the user dragged on this output (`sizes`), else `width` × twice that (WebCard's own rule).
    readonly property var box: (d.sizes && d.sizes[outName]) || null
    readonly property int phoneW: box ? box.width : (geo.width || 412)
    readonly property int phoneH0: box ? box.height : 2 * phoneW
    readonly property int largePct: geo.large || 90
    readonly property bool large: d.size === "large"
    // W69: the page style the cards wear (absent = phone), the host's card's too.
    readonly property string pageStyle: d.page_style || "phone"
    readonly property bool pinned: d.pinned === true
    // I91: the settings the configuration forces, each with its source (`forced` on mod.webdock; absent when none is).
    readonly property var forced: d.forced || ({})
    readonly property bool reserve: d.reserve === true
    readonly property bool wantFocus: d.engaged === true && open
    // W78 (docs/ux/webdock.md "Local mode"): the strip lists the shell's own views; `strip` names them (the daemon's).
    readonly property bool local: d.content === "local"
    // The switch shows while a mod that is on offers a view (a panel or a desk card), or while Local is on (the way back):
    // no inert key on a shell without local content (Kanso).
    Watch { doc: "mods" }
    readonly property bool hasLocal: {
        var list = (Store.docs["mods"] && Store.docs["mods"].mods) || []
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === "webdock" || list[i].state !== "enabled") continue
            for (var key in (list[i].qml || ({})))
                if (key.indexOf("panel:") === 0 || key.indexOf("desk:") === 0) return true
        }
        return false
    }
    readonly property bool showSwitch: local || hasLocal
    onShowSwitchChanged: refreshRows()

    // ---- the pins and the card's subject ----
    readonly property var pins: d.pins || []
    // W76: the pins the strip lists: a temporary page (from "+", or unpinned but kept open) is shown, never listed. Made
    // in refreshRows, and replaced only when the rows change (a binding made a new list on every patch of the document).
    property var listed: []
    readonly property string shownId: d.shown || ""
    readonly property var shownPin: pinOf(shownId)
    readonly property string hostState: (d.host && d.host.state) || "off"
    readonly property string hostReason: (d.host && d.host.reason) || ""
    readonly property var view: viewOf(shownPin && shownPin.kind === "view" ? String(shownPin.target) : "")
    property var rowList: []
    onPinsChanged: refreshRows()
    onLocalChanged: refreshRows()
    // Whether the enabled mod `mod` has a QML file for `provide` (the `mods` document's `qml` map; frontend/core/mods.js
    // qmlOf, which a mod's QML does not import).
    function provides(mod, provide) {
        var list = (Store.docs["mods"] && Store.docs["mods"].mods) || []
        for (var i = 0; i < list.length; i++)
            if (list[i].id === mod) return typeof (list[i].qml || ({}))[provide] === "string"
        return false
    }

    function pinOf(id) {
        for (var i = 0; i < pins.length; i++)
            if (pins[i].id === id) return pins[i]
        return null
    }
    function indexOfPin(id) {
        for (var i = 0; i < listed.length; i++)
            if (listed[i].id === id) return i
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
        var out = [], ps = []
        // (W78: `strip` lists the mode's pins while it is not every pin; absent, every pin but a temporary page)
        var only = Array.isArray(d.strip) ? d.strip : null
        for (var k = 0; k < pins.length; k++)
            if (pins[k].temporary !== true && (only === null || only.indexOf(pins[k].id) >= 0)) ps.push(pins[k])
        for (var i = 0; i < ps.length; i++) {
            if (i > 0 && ps[i].kind !== ps[i - 1].kind) out.push({ kind: "divider" })
            out.push({ kind: "pin", pin: ps[i] })
        }
        if (ps.length > 0) out.push({ kind: "divider" })
        if (showSwitch) out.push({ kind: "ctl", ctl: "content" })
        out.push({ kind: "ctl", ctl: "pin" }, { kind: "ctl", ctl: "add" }, { kind: "ctl", ctl: "settings" })
        if (JSON.stringify(out) !== JSON.stringify(rowList)) {
            rowList = out; listed = ps
            if (debugLog && open) stripLog.restart()
        }
    }
    Component.onCompleted: { refreshRows(); Qt.callLater(function () { dock.born = true }) }

    // ---- what the panel beside the strip shows ----
    readonly property bool viewCard: extended && view !== null
    readonly property bool coldCard: extended && shownPin !== null && shownPin.kind === "web" && hostState !== "ready"
    readonly property bool emptyCard: extended && listed.length === 0 && shownPin === null
    // The add form and a pin's menu take the card's place beside the strip, whatever the card shows.
    property string side: ""         // "" | "add" | "menu" | "local" (W78: the local chooser)
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
    onOpenChanged: { if (!open) side = ""; else pulseSpent = false; if (open && debugLog) stripLog.restart() }
    // (W64: a panel that closes while the strip stays keeps its content until its form or slide has put it away)
    readonly property string kind: !open ? held : kindNow !== "" ? kindNow : (cardReveal > 0.001 ? held : "")

    // ---- geometry: WebCard's sizes (phone, large) and the strip's centred span, in the window's usable height ----
    readonly property real gap: Theme.gap
    // A reserved strip (`reserve` with a pinned strip) needs the zone's own anchors (layer shell ignores the zone with
    // both ends anchored), so there the output's height stands in for a top or bottom edge, as before.
    readonly property bool spans: !sideways && surfaceUp && !(reserve && pinned)
    readonly property real spanH: spans ? height : outH
    // The card's length along a top or bottom edge is the usable width (`along`), as a side edge's is the usable height.
    readonly property real cardW: large ? Math.round((sideways ? outW : along) * largePct / 100) : phoneW
    // A side edge is limited by the window's own length; a top or bottom edge by the usable height it spans, less the
    // strip (the card stands beyond it, across the edge) and a gap at the far end, as WebCard leaves (I100).
    readonly property real cardH: sideways
        ? (large ? Math.round(along - 2 * gap) : Math.min(phoneH0, Math.round(along - 2 * gap)))
        : (large ? Math.round(spanH - stripPx - 2 * gap) : Math.min(phoneH0, Math.round(spanH - stripPx - 2 * gap)))
    // Test-only (KURASHI_WEBDOCK_DEBUG=1, test-dock.sh): the card's height and the window's, to check it fills the area.
    readonly property bool debugLog: Quickshell.env("KURASHI_WEBDOCK_DEBUG") === "1"
    function logGeometry() { if (debugLog) console.log("webdock-debug dock", edge, cardH, Math.round(height)) }
    onCardHChanged: logGeometry()
    // (test only, W76: where each listed pin's tile is in the window once the strip is in, and the window's size —
    // test-card.sh right-clicks a tile for its menu)
    Timer {
        id: stripLog
        interval: 800
        onTriggered: {
            for (var i = 0; i < dock.listed.length; i++) {
                var t = stripItem.tileOf(String(dock.listed[i].id))
                if (!t) continue
                var p = t.mapToItem(null, t.width / 2, t.height / 2)
                console.log("webdock-debug strip " + dock.listed[i].id + " " + Math.round(p.x) + " " + Math.round(p.y) + " "
                    + Math.round(dock.width) + " " + Math.round(dock.height))
            }
            // (W78: the switch and "+", and what the strip lists — test-card.sh's part "local")
            var ctls = ["content", "add"]
            for (var j = 0; j < ctls.length; j++) {
                var c = stripItem.tileOf(ctls[j])
                if (!c) continue
                var q = c.mapToItem(null, c.width / 2, c.height / 2)
                console.log("webdock-debug strip ctl:" + ctls[j] + " " + Math.round(q.x) + " " + Math.round(q.y) + " "
                    + Math.round(dock.width) + " " + Math.round(dock.height))
            }
            console.log("webdock-debug rows " + (dock.local ? "local" : "online") + " "
                + dock.listed.map(function (x) { return x.id }).join(","))
        }
    }
    onHeightChanged: logGeometry()
    onEdgeChanged: logGeometry()
    readonly property real sideSize: 300
    readonly property bool kindSide: kind.indexOf("side") === 0
    // A panel across its edge (its thickness) and along it.
    // (W76: the pin's menu is 300 wide and 460 tall: its page entries came first)
    readonly property real menuH: Math.min(380, (sideways ? along : spanH - stripPx) - 2 * gap)
    // (W78: the local chooser is a list: as long along the edge as the card's phone height allows, up to 460 px)
    readonly property real localH: Math.min(460, Math.round(along - 2 * gap))
    readonly property real sideAcross: kind === "side-menu" && !sideways ? menuH : (kind === "side-local" && !sideways ? localH : sideSize)
    readonly property real sideAlong: kind === "side-menu" && sideways ? menuH : (kind === "side-local" && sideways ? localH : sideSize)
    readonly property real panelAcross: kind === "" ? 0 : (kindSide ? sideAcross : (sideways ? cardW : cardH))
    readonly property real panelAlong: kind === "" ? 0 : (kindSide ? sideAlong : (sideways ? cardH : cardW))
    readonly property real panelAlong0: (along - panelAlong) / 2
    readonly property real stripAlong0: (along - stripLen) / 2
    readonly property real stripMax: along - 2 * gap
    readonly property real stripLen: Math.min(stripItem.contentLen, stripMax)
    readonly property real restT: 4
    // K83 (W64; docs/ux/motion-engine.md §6): the strip slides in and out on the profile's `fast` curve (a Glide; it stops
    // at its rest, no overshoot off the edge); the card or side panel opens and closes in the `panel` form (`pRun`, the
    // panel's FormHost: shape and sheet forms, hinged on the strip's side), else slides on the profile's open and close
    // curves — once the strip is a quarter in, so it follows the strip. Reduced motion (profile none or reduced) fades
    // both over `fadeMs`. The window keeps its size until both have finished. Nothing runs at rest (Ma).
    // (made by the first reveal, the window is open from its start: the strip and the card come in from its first turn
    // instead of standing there at once)
    property bool born: false
    readonly property bool shownNow: born && open
    readonly property Glide stripGlide: Glide { role: "fast"; to: dock.shownNow ? 1 : 0 }
    property real stripFade: shownNow ? 1 : 0
    Behavior on stripFade { enabled: dock.reduced; NumberAnimation { duration: dock.fadeMs } }
    readonly property real reveal: reduced ? stripFade : Math.min(1, stripGlide.value)
    readonly property bool panelGo: born && panelUp && (reduced || reveal >= 0.25)
    readonly property Glide cardGlide: Glide { to: dock.panelGo ? 1 : 0 }
    readonly property SurfaceForm pRun: SurfaceForm {
        surface: "panel"
        shapes: ["expand", "iris", "stamp", "outline"]
        // (reduced motion keeps its fade: no form; a slide still in flight keeps its way)
        want: dock.panelGo && !dock.reduced
        hold: !formed && dock.cardGlide.running && dock.cardGlide.value > 0.001 && dock.cardGlide.value < 0.999
    }
    readonly property bool cardFormDraws: pRun.formed && (pRun.busy || pRun.want)
    property real cardFade: born && panelUp ? 1 : 0
    Behavior on cardFade { enabled: dock.reduced; NumberAnimation { duration: dock.fadeMs } }
    readonly property real cardReveal: reduced ? cardFade : cardFormDraws ? 1 : cardGlide.value
    readonly property bool surfaceUp: open || reveal > 0.001 || cardReveal > 0.001
    // Across the edge: the strip, its grace, and the panel (kept while it slides out, see `held`).
    readonly property real thick: surfaceUp ? stripPx + grace + panelAcross : restT
    readonly property real loAlong: Math.max(0, (panelUp ? Math.min(stripAlong0, panelAlong0) : stripAlong0) - grace)
    readonly property real hiAlong: Math.min(along, (panelUp ? Math.max(stripAlong0 + stripLen, panelAlong0 + panelAlong)
        : stripAlong0 + stripLen) + grace)

    // ---- the window ----
    implicitWidth: sideways ? thick : 0
    // Spanned, the compositor sets the height between the bars and ignores this request; a constant here keeps the
    // window's height out of its own card's size (a binding loop otherwise, I100).
    implicitHeight: sideways ? 0 : (spans ? outH : thick)
    // A top or bottom edge spans the usable height while it is up (`spans`): anchored to both ends, the compositor
    // stretches the window between the bars, as a side edge's window is stretched along its length, so the card keeps a
    // bar on its axis clear (I100). Idle it is thin again (4 px), as it always was.
    anchors.top: edge !== "bottom" || spans
    anchors.bottom: edge !== "top" || spans
    anchors.left: edge !== "right"
    anchors.right: edge !== "left"
    color: "transparent"
    // Normal placement: the usable area (below a top bar). The strip reserves its width only when it is pinned and reserve is on.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: reserve && pinned && open ? stripPx : 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "kurashi-webdock-shell"
    WlrLayershell.keyboardFocus: !open ? WlrKeyboardFocus.None : (asksKeys ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)
    mask: open ? activeRegion : emptyRegion

    Region { id: emptyRegion }
    Region {
        id: activeRegion
        x: dock.sideways ? (dock.edge === "right" ? dock.width - dock.thick : 0) : dock.loAlong
        y: dock.sideways ? dock.loAlong : (dock.edge === "bottom" ? dock.height - dock.thick : 0)
        width: dock.sideways ? dock.thick : dock.hiAlong - dock.loAlong
        height: dock.sideways ? dock.hiAlong - dock.loAlong : dock.thick
    }

    // ---- intents ----
    function send(action, args) { Store.act(action, args || ({})) }

    // Engaged: the dock has keyboard focus while it is open. A hide is a loss of focus for the daemon too (it clears
    // `engaged` itself), so a reveal with the focus still inside reports engaged again.
    readonly property bool focusInside: open && scope.activeFocus
    onFocusInsideChanged: send("webdock.engage", { on: focusInside })

    // Hover parts (the strip and the card): on change only.
    readonly property bool stripIn: stripHover.hovered && open
    readonly property bool cardIn: panelHover.hovered && panelUp
    onStripInChanged: hover("strip", stripIn)
    onCardInChanged: hover("card", cardIn)
    property var sentHover: ({ strip: false, card: false })
    function hover(part, inside) {
        if (sentHover[part] === inside) return
        sentHover[part] = inside
        send("webdock.hover", { part: part, inside: inside, output: outName })
    }

    // Keyboard: the front part takes focus when the daemon says `engaged` (a toggle), the card when extended, else the strip.
    onWantFocusChanged: if (wantFocus) Qt.callLater(focusFront)
    function focusFront() {
        if (panelUp && panelLoader.item) panelLoader.item.forceActiveFocus()
        else stripItem.focusFirst()
    }
    // I98: a keybind reveal (`engaged`, with the mode) asks for the keyboard exclusively until the compositor has given the
    // window the focus, then relaxes to on-demand, so a click elsewhere still moves the focus. An on-demand surface takes
    // the focus only on a click, so the first keys after the reveal went to the window that had it. A pulse nobody answers
    // is dropped after a second; it is spent once the window has been active in this reveal, so a click elsewhere is never
    // taken back. The host card runs the same rule for a web pin (WebCard) while it is the front part.
    property bool winActive: false
    property bool pulseSpent: false
    readonly property bool hostFront: extended && shownPin !== null && shownPin.kind === "web" && hostState === "ready"
    readonly property bool asksKeys: open && wantFocus && !winActive && !pulseSpent && !hostFront
    onAsksKeysChanged: if (asksKeys) pulseTimer.restart(); else pulseTimer.stop()
    Timer { id: pulseTimer; interval: 1000; onTriggered: dock.pulseSpent = true }

    FocusScope {
        id: scope
        anchors.fill: parent

        // The window's keyboard focus as the compositor gives it (`Window.active`): the front part takes it at once, so a
        // key that follows the grant does not wait for the next turn of the event loop (I98).
        Item {
            Window.onActiveChanged: {
                dock.winActive = Window.active
                if (Window.active) dock.pulseSpent = true
                if (Window.active && dock.wantFocus) dock.focusFront()
            }
        }

        // The strip: slides in from the edge (reduced motion: fades). Its panel is the bar's surface, rounded.
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
            Rectangle {
                anchors.fill: parent
                radius: Theme.rLg
                color: Theme.surfaceAlpha
                // The chrome outlines the strip like every block (K42, K45: ink, rim or line); flat has none.
                border.width: Theme.outlineW
                border.color: Theme.outlineColor
            }

            Strip {
                id: stripItem
                anchors.fill: parent
                vertical: dock.sideways
                thick: dock.stripPx
                rows: dock.rowList
                shownId: dock.shownId
                pinned: dock.pinned
                pinForced: forced.pinned !== undefined && forced.pinned !== null
                pinForcedBy: String(forced.pinned || "")
                local: dock.local
                contentForcedBy: forced.content !== undefined && forced.content !== null ? String(forced.content) : ""
                onContentToggled: { dock.side = ""; dock.send("webdock.content", {}) }
                edge: dock.edge
                panelOpen: dock.panelUp
                onPinSelected: id => dock.send("webdock.select", { pin: id, output: dock.outName })
                // (W76: over a site's card the menu would open under the host's window: the card closes first, the page stays)
                onPinMenu: id => { if (dock.hostFront) dock.send("webdock.collapse", {}); dock.menuId = id; dock.sideOwner = id; dock.side = "menu" }
                onPinToggled: dock.send("webdock.pin", { on: !dock.pinned })
                // W76: "+" opens a new temporary page in the card, its address field where the title is (the host's).
                // W78: in Local, "+" offers the mods' views (the local chooser beside the strip) instead.
                onAddPressed: {
                    if (dock.local) { dock.sideOwner = "add"; dock.side = "local" }
                    else dock.send("webdock.browse", { place: "edge", output: dock.outName })
                }
                onSettingsPressed: dock.send("settings.open", { key: "mods.webdock.pins" })
                onBackPressed: dock.send("webdock.back", {})
                onTabPressed: if (dock.panelUp && panelLoader.item) panelLoader.item.forceActiveFocus()
            }
        }
        // K83 (W64): the panel's form host, window-sized (as the dock's and the sidebar's: its layers keep the card's
        // material registered with the output) — a sheet form captures `panelSrc` (the panel's box of `panelDraw`), hinged
        // on the strip's side; a shape form draws it through its mask. Its origin is the strip's tile that opened it.
        FormHost {
            id: pHost
            anchors.fill: parent
            surface: "panel"
            edge: dock.edge
            direction: dock.pRun.dir
            // (only while the form draws the panel: a form latched by the last transition stays at its rest meanwhile, and
            // reduce motion fades without one)
            progress: dock.pRun.sheet && dock.cardFormDraws ? dock.pRun.p : 1
            visible: !(dock.pRun.sheet && dock.cardFormDraws) || dock.pRun.p > 0
            source: panelSrc
            origin: dock.panelOrigin
            ShapeLayer {
                anchors.fill: parent
                run: dock.pRun
                edge: dock.edge
                Item {
                    id: panelDraw
                    anchors.fill: parent
                    // The card or the side panel, beside the strip: it follows the strip, in the panel's form or sliding.
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
                            sourceComponent: dock.kind === "side-menu" ? menuC : dock.kind === "side-local" ? localC : (dock.kind === "side-add" ? addC
                                : (dock.kind === "view" ? viewC : (dock.kind === "cold" ? coldC : emptyC)))
                        }
                    }
                }
                // While a sheet form warps the panel: the window's drawing in one layer, the panel's box of it the form's
                // capture — so p = 1 is the rest frame, material and all.
                SheetRest {
                    id: pRest
                    anchors.fill: parent
                    on: pHost.sheetSolid
                    draw: panelDraw
                    body: Qt.rect(Math.round(panelBox.x), Math.round(panelBox.y), Math.round(panelBox.width),
                        Math.round(panelBox.height))
                    hingeY: -1e6
                    k: pHost.sheetFillets
                }
                Item {
                    id: panelSrc
                    x: pRest.body.x
                    y: pRest.body.y
                    width: pRest.body.width
                    height: pRest.body.height
                    clip: true
                    SheetRest.Body { rest: pRest }
                }
            }
        }
    }

    // ---- the panel's form (K83, W64) ----
    // The tile the panel opens from (a pin's, or the add control's), taken when it starts to open and kept while it closes.
    property string originKey: ""
    onPanelGoChanged: if (panelGo) originKey = side !== "" ? sideOwner : shownId
    // Its box in the window's item px, then in the form's frame (ShapeLayer on the window: x along the edge, y away from the
    // screen's edge; the panel stands `stripPx` off it, its hinge there).
    // (worked out only while a form opens or closes the panel: the strip's slide re-reads it every frame otherwise — Ma, and
    // the JS garbage of a binding per frame showed as USS growth over 20 reveals)
    readonly property rect panelOrigin: {
        if (originKey === "" || !(pRun.want || pRun.busy)) return Qt.rect(0, 0, 0, 0)
        void reveal; void rowList; void width; void height
        var t = stripItem.tileOf(originKey)
        if (!t) return Qt.rect(0, 0, 0, 0)
        var p = t.mapToItem(pHost, 0, 0)
        return Qt.rect(p.x, p.y, t.width, t.height)
    }
    function frameOf(ix, iy) {
        if (sideways) return Qt.point(iy, edge === "right" ? width - ix : ix)
        return Qt.point(ix, edge === "bottom" ? height - iy : iy)
    }
    readonly property bool hasOrigin: panelOrigin.width > 0
    readonly property point originMid: frameOf(panelOrigin.x + panelOrigin.width / 2, panelOrigin.y + panelOrigin.height / 2)
    readonly property real panelMid: panelAlong0 + panelAlong / 2
    Binding { target: dock.pRun; property: "fromCx"; value: dock.hasOrigin ? dock.originMid.x : dock.panelMid }
    Binding { target: dock.pRun; property: "fromW"; value: dock.hasOrigin ? (dock.sideways ? dock.panelOrigin.height : dock.panelOrigin.width) : dock.panelAlong * 0.3 }
    Binding { target: dock.pRun; property: "fromTop"; value: dock.stripPx }
    Binding { target: dock.pRun; property: "fromFoot"; value: dock.stripPx }
    Binding { target: dock.pRun; property: "fromR"; value: Theme.rSm }
    Binding { target: dock.pRun; property: "toCx"; value: dock.panelMid }
    Binding { target: dock.pRun; property: "toW"; value: dock.panelAlong }
    Binding { target: dock.pRun; property: "toTop"; value: dock.stripPx }
    Binding { target: dock.pRun; property: "toFoot"; value: dock.stripPx + dock.panelAcross }
    Binding { target: dock.pRun; property: "toR"; value: Theme.rLg }
    Binding { target: dock.pRun; property: "edgeY"; value: dock.stripPx }
    // (an iris opens at the tile: its middle, on the strip's side of the hinge)
    Binding { target: dock.pRun; property: "pressX"; value: dock.hasOrigin ? dock.originMid.x : NaN }
    Binding { target: dock.pRun; property: "pressY"; value: dock.hasOrigin ? dock.originMid.y : NaN }

    // ---- the panels' content ----
    Component {
        id: viewC
        Card {
            id: vcard
            anchors.fill: parent
            title: dock.shownPin ? String(dock.shownPin.title || "") : ""
            large: dock.large
            style: dock.pageStyle
            edge: dock.edge
            pinned: dock.pinned
            pinForcedBy: dock.forced.pinned !== undefined && dock.forced.pinned !== null ? String(dock.forced.pinned) : ""
            onPinToggled: dock.send("webdock.pin", { on: !dock.pinned })
            onSizeChosen: size => dock.send("webdock.size", { size: size })
            onCollapse: dock.send("webdock.collapse", {})
            onEscaped: dock.send("webdock.back", {})
            // (W78: a mod's desk card stands in where it has no panel of that name — notes, lyrics: the sidebar's rule)
            Watch { doc: "mods" }
            readonly property bool asDesk: dock.view !== null
                && !dock.provides(dock.view.mod, "panel:" + dock.view.panel)
                && dock.provides(dock.view.mod, "desk:" + dock.view.panel)
            ModLoader {
                id: viewBody
                anchors.fill: parent
                // (test only, W78: what the view card loaded)
                onItemChanged: if (dock.debugLog) console.log("webdock-debug view " + provide + " " + (item !== null))
                provide: dock.view ? (vcard.asDesk ? "desk:" : "panel:") + dock.view.panel : ""
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
            title: dock.shownPin ? String(dock.shownPin.title || (dock.shownPin.temporary === true ? I18n.tr("webdock.browse") : "")) : ""
            large: dock.large
            style: dock.pageStyle
            edge: dock.edge
            pinned: dock.pinned
            pinForcedBy: dock.forced.pinned !== undefined && dock.forced.pinned !== null ? String(dock.forced.pinned) : ""
            onPinToggled: dock.send("webdock.pin", { on: !dock.pinned })
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
            style: dock.pageStyle
            edge: dock.edge
            pinned: dock.pinned
            pinForcedBy: dock.forced.pinned !== undefined && dock.forced.pinned !== null ? String(dock.forced.pinned) : ""
            onPinToggled: dock.send("webdock.pin", { on: !dock.pinned })
            onCollapse: dock.send("webdock.collapse", {})
            onEscaped: dock.send("webdock.back", {})
            Notice {
                anchors.fill: parent
                text: I18n.tr(dock.local ? "webdock.local.empty" : "webdock.empty")
                actionLabel: I18n.tr(dock.local ? "webdock.local.empty.add" : "webdock.dock.empty.add")
                onActionPressed: { dock.sideOwner = "add"; dock.side = dock.local ? "local" : "add" }
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
        id: localC
        LocalForm {
            anchors.fill: parent
            pins: dock.pins
            onOpened: pin => { dock.side = ""; if (pin !== "") dock.send("webdock.open", { pin: pin, output: dock.outName }) }
            onSettingsPressed: { dock.side = ""; dock.send("settings.open", { page: "mods" }) }
            onCancelled: dock.side = ""
        }
    }
    Component {
        id: menuC
        PinMenu {
            anchors.fill: parent
            pin: dock.pinOf(dock.menuId) || ({})
            index: dock.indexOfPin(dock.menuId)
            count: dock.listed.length
            onMoved: to => { dock.send("webdock.move", { pin: dock.menuId, to: to }); dock.side = "" }
            onRemoved: { dock.send("webdock.remove", { pin: dock.menuId }); dock.side = "" }
            // W76: the page's own entries (docs/ux/webdock.md "Round three": the pin's menu)
            onReloaded: { dock.send("webdock.reload", { pin: dock.menuId }); dock.side = "" }
            onRetargeted: { dock.send("webdock.retarget", { pin: dock.menuId }); dock.side = "" }
            onUnpinned: { dock.send("webdock.unpin", { pin: dock.menuId }); dock.side = "" }
            onClosed: dock.side = ""
        }
    }
}
