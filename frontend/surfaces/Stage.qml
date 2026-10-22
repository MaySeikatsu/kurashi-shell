import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../core"
import "../core/mods.js" as Mods
import "../components"
import "../components/expanded"
import "../components/island"

// Stage (ARCHITECTURE §4): overlay layer surface holding popups / OSD / island expansions, the
// session menu, the tray item menus (K23), the quick settings card (K24) and the hover peeks of bar items (K35). Sized to its content
// (K16: a full-output buffer cost ~80 MiB), top-centred under the Island, or hung from the bar's
// tray end for a tray menu. One instance, retargeted by shell.qml to the output that asked for it.
// Later OSD/toasts: grow the implicit size to the union of their cards, or add sibling content-sized
// Stages; never a full-output one.
//
// Idle = silent (Ma) without unmapping: map/unmap cycles of this window left ~5 MiB of heap behind
// per cycle (measured, K16), a permanently mapped, fully transparent, input-less surface costs
// nothing (0 renders, 0 commits; the compositor just skips it). Hidden = card not visible, empty
// input and blur regions, no keyboard focus. Reveal starts on the first presented frame.
// W21 (docs/ux/island.md "Session 9 morph"): under a top or bottom bar the island's card is not slid in, it grows out of
// the island. The Stage then also covers the bar's strip above the card (margin 0, still content-sized: the card's width
// and the strip's height, K16) and draws one shape (MorphShape) that starts at the bar pill's exact rect (IslandGeom),
// springs to the card's rect (width and height on their own springs: on the way out width leads, on the way back height
// does, Capsule) and is joined to the bar by a liquid neck (Vitreus). The pill's face stays in the shape's head, inside the
// bar, where it was; the view fades in once the shape has nearly grown, and fades out first when it folds back. While the
// shape is out the bar's pill is not drawn (IslandGeom.takenOn), so there is one island. Retargets keep the springs'
// velocity (interruptible); Theme.springOn false snaps. Side bars keep the slide.
// K45/I115: where the bar's groups float as blocks of their own (keycap and soft chrome: no strip to grow out of), the
// shape keeps the island's bar block as its head and the card grows out from under it, joined by a neck: one outline
// round both, which the keycap's ring and hard shadow and the soft shadow follow. Its fill is the panel's (I114:
// translucent under glass), its layers never lie under one another.
PanelWindow {
    id: stage

    // K59: this window's tile set, shared by its reliefs (components/TileSheet.qml), and the pointer light's sensor.
    // K61: the card's carry while it slides (a side bar's Stage): every relief on it takes its sheet along; 0 at rest
    // and while the island's shape draws the card (the shape's relief carries its own, `shapeCarry`).
    property var tileSheet: tilesLoader.item
    readonly property point sheetCarry: Qt.point(0, morphMode ? 0 : card.y)
    Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
    LightSense {}

    // The island panel is wanted (shell.qml sets it after it picked the output, with the session
    // menu and the tray menu).
    property bool want: false
    // Which one the card shows comes from runtime.ui, where the daemon keeps the open panel (K23).
    Watch { doc: "runtime.ui" }
    readonly property var ui: Store.docs["runtime.ui"] || ({})
    readonly property bool sessionWanted: ui.panel === "session"
    readonly property bool trayWanted: ui.panel === "tray"
    // shell.qml's `want` does not cover the quick panel (K24), so the Stage follows runtime.ui for it.
    readonly property bool quickWanted: ui.panel === "quick"
    // A native mod's panel (K26): `mod:<id>:<panel>` shows its Panel.qml, for as long as the mods document names it.
    // Always watched, not by a binding on runtime.ui: the mods document is what says whether the panel exists, and
    // it starts no service.
    Watch { doc: "mods" }
    readonly property var modsDoc: Store.docs["mods"]
    readonly property var panelRef: Mods.panelOf(ui.panel)
    readonly property bool modWanted: panelRef !== null && Mods.qmlOf(modsDoc, "panel:" + panelRef.panel, panelRef.mod) !== ""
    readonly property bool open: want || quickWanted || modWanted
    // K24: the island card shows the expanded view of the face the daemon latched when it opened. A core face
    // without one gets the generic card; a mod face loads its `island-face:<name>:expanded` (K28), or the generic card.
    // power and bluetooth open their quick settings pages, not the generic card (I44).
    readonly property var expandedFaces: ["media", "notifications", "clock", "volume", "brightness", "power", "bluetooth"]
    readonly property string islandKind: expandedFaces.indexOf(ui.face) >= 0 ? ui.face : (ui.face ? "modface" : "island")
    readonly property string wantedKind: sessionWanted ? "session" : (trayWanted ? "tray"
        : (quickWanted ? "quick" : (modWanted ? "mod" : (want ? islandKind : ""))))
    // Latched while the card slides out, as contentKind is: which mod panel, and which mod face's view, it shows.
    property string shownPanelMod: ""
    property string shownPanel: ""
    property string shownFaceView: ""
    // Read from `ui` itself: panelRef is a binding that may not have been re-evaluated yet when this handler runs,
    // and a stale null there left the panel unlatched (the card opened empty).
    onUiChanged: {
        var p = Mods.panelOf(ui.panel)
        if (p !== null) { shownPanelMod = p.mod; shownPanel = "panel:" + p.panel }
        if (ui.face) shownFaceView = "island-face:" + ui.face + ":expanded"
    }
    // Content the card shows. Latched while the card slides out, so a closing menu does not flash other content.
    property string contentKind: "island"
    // Not while the panel is being closed: runtime.ui loses its face a moment before shell.qml drops `want`, and the generic
    // card must not flash in the closing island (W21).
    onWantedKindChanged: if (wantedKind !== "" && (wantedKind !== "island" || !!ui.panel || ui.popup === true)) contentKind = wantedKind
    // The card keeps the Stage's one keyboard focus across content changes and reopenings (the menus
    // are driven from it), so it takes focus back whenever the content swaps or the Stage opens.
    onContentKindChanged: Qt.callLater(function () { card.forceActiveFocus() })

    // The card's view per kind, one component each. The Loader makes only the current one, and only
    // while the card is on screen, so a view that is not shown holds no subscription (Ma).
    readonly property var views: ({
        island: genericView, media: mediaView, notifications: notificationsView, clock: clockView,
        volume: volumeView, brightness: brightnessView, quick: quickView, mod: modPanelView, modface: modFaceView,
        power: powerView, bluetooth: bluetoothView
    })
    readonly property bool viewing: views[contentKind] !== undefined
    // A view that draws its own chrome (`ownChrome`, the quick settings phone): no card fill, border, padding or Close row
    // around it; the island's shape (or the slide) still brings it in.
    readonly property bool ownChrome: viewing && view.item !== null && view.item.ownChrome === true
    readonly property int cardPad: ownChrome ? 0 : Theme.pad + 4
    // A mod panel's root may declare `property int cardWidth` (the card's outer width, contract row 66): the card
    // takes it within 360..720 px and the output's width; the panel gets the card's content width.
    readonly property var modPanel: contentKind === "mod" && view.item ? view.item.item : null
    readonly property int modCardWidth: {
        var want = modPanel && modPanel.cardWidth > 0 ? modPanel.cardWidth : 360
        var room = screen ? screen.width - 2 * Theme.pad : 720
        return Math.max(360, Math.min(want, 720, room))
    }
    Component { id: genericView; GenericView {} }
    Component { id: mediaView; MediaView {} }
    Component { id: notificationsView; NotificationsView {} }
    Component { id: clockView; ClockView {} }
    Component { id: volumeView; VolumeView {} }
    Component { id: brightnessView; BrightnessView {} }
    Component { id: quickView; QuickPanel {} }
    // The power and bluetooth faces' expanded views are the quick settings pages (I44): the card opens on that page.
    Component { id: powerView; QuickPanel { startPage: "power" } }
    Component { id: bluetoothView; QuickPanel { startPage: "bluetooth" } }
    // A mod's Panel.qml (K26): the card's one Loader makes it, ModLoader destroys it when the mod is disabled.
    Component {
        id: modPanelView
        ModLoader { provide: stage.shownPanel; mod: stage.shownPanelMod }
    }
    // A mod face's expanded view (K28, `island-face:<name>:expanded`), or the generic card when the mod has none.
    Component {
        id: modFaceView
        Column {
            id: faceCol
            width: parent.width
            spacing: Theme.gap
            ModLoader {
                id: faceView
                width: faceCol.width
                height: implicitHeight
                visible: resolved !== ""
                provide: stage.shownFaceView
            }
            GenericView { visible: faceView.resolved === "" }
        }
    }

    // The bar of this output: the card sits just under a top bar, just above a bottom bar, and at
    // the screen edge otherwise (no bar, or a side bar a centred card does not meet).
    BarConfig { id: bars; screen: stage.screen }
    // A tray menu hangs from the tray's end of the bar: the bar's right end on a top or bottom bar,
    // the bottom end beside a side bar (the tray is the last thing in those columns).
    readonly property bool aligned: contentKind === "tray"
    readonly property bool menuBeside: aligned && bars.vertical

    readonly property int slide: 12     // px the card travels while revealing
    property real p: 0                  // reveal progress 0..1
    property bool gate: false           // waiting for the first presented frame
    property bool shown: false          // card is on screen (opening, open or closing)

    // Only one vertical edge anchored -> the compositor centres the surface horizontally. A peek is anchored to the side of
    // its own bar instead (K35, I67): at its own x under a top bar or above a bottom bar, at its own y beside a side bar.
    anchors {
        top: peekLayout ? shownEdge !== "bottom" : (!bars.atBottom && !menuBeside)
        bottom: peekLayout ? shownEdge === "bottom" : (bars.atBottom || menuBeside)
        left: peekLayout ? shownEdge !== "right" : (menuBeside && bars.edge === "left")
        right: peekLayout ? shownEdge === "right" : (aligned && (!bars.vertical || bars.edge === "right"))
    }
    margins {
        top: peekLayout ? (shownEdge === "top" ? peekInset : (peekSide ? peekTop : 0)) : (morphLayout ? 0 : bars.topInset)
        bottom: peekLayout ? (shownEdge === "bottom" ? peekInset : 0)
            : (morphLayout ? 0 : (menuBeside ? Theme.pad : bars.bottomInset))
        left: peekLayout ? (shownEdge === "left" ? peekBarClear : (shownEdge === "right" ? 0 : peekLeft))
            : (menuBeside ? Theme.barH + Theme.gap : 0)
        right: peekLayout ? (shownEdge === "right" ? peekBarClear : 0)
            : (aligned ? (menuBeside ? Theme.barH + Theme.gap : Theme.pad) : 0)
    }
    implicitWidth: peekLayout ? peekCard.width : (morphLayout ? morphW : card.width)
    implicitHeight: peekLayout ? peekCard.height : (morphLayout ? morphH : card.height)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "kurashi-stage"
    color: "transparent"
    mask: peekLayout ? peekRegion : (shown ? cardRegion : emptyRegion)
    // The island's shape is opaque and changes size every frame of its morph: no blur behind it.
    BackgroundEffect.blurRegion: peekLayout ? peekRegion : (shown && !morphMode ? cardRegion : emptyRegion)
    Region { id: cardRegion; item: card }
    Region { id: peekRegion; item: peekCard }
    Region { id: emptyRegion }

    onOpenChanged: {
        if (open) {
            // Content first: a menu closed a moment ago must not show for a frame.
            contentKind = wantedKind === "" ? "island" : wantedKind
            pillGeom = IslandGeom.pillOf(outName)
            Qt.callLater(function () { card.forceActiveFocus() })
            anim.stop()
            handBack.stop()
            if (morphMode) {
                // The shape starts as the pill (no spring yet) and grows from the first presented frame on; reopened
                // while it folds back, it grows again from where it is, with its velocity.
                if (!shown) { mw = 0; mh = 0; p = 1; gate = true; shown = true }
                else { expanding = true; mw = 1; mh = 1 }
            } else if (!shown) { p = 0; gate = true; shown = true }
            else { anim.from = p; anim.to = 1; anim.start() }
        } else if (shown) {
            gate = false
            if (morphMode) { expanding = false; mw = 0; mh = 0; checkFolded() }
            else { anim.stop(); anim.from = p; anim.to = 0; anim.start() }
        }
    }
    NumberAnimation {
        id: anim
        target: stage; property: "p"
        duration: Theme.stdMs
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve
        onFinished: if (stage.p <= 0 && !stage.open) stage.shown = false
    }
    Connections {
        target: card.Window.window
        function onFrameSwapped() {
            if (stage.gate) {
                stage.gate = false
                if (stage.morphMode) { stage.taken = true; stage.expanding = true; stage.mw = 1; stage.mh = 1 }
                else { anim.from = stage.p; anim.to = 1; anim.start() }
            }
            if (stage.peekGate) { stage.peekGate = false; peekAnim.from = stage.peekP; peekAnim.to = 1; peekAnim.start() }
        }
    }

    // Watched only while their content is on screen (Ma): a hidden card holds no subscription. The
    // tray menu reads its item's title from svc.tray; the island views and the quick card watch their own docs.
    readonly property bool trayLive: shown && contentKind === "tray"
    Watch { doc: "svc.tray"; active: stage.trayLive }

    // A failed action shows its translated text, never the daemon's raw msg: msg is an i18n key
    // (error.*). A key without text falls back to the panel's own line.
    function errorText(err, fallback) {
        var k = err && err.msg ? String(err.msg) : ""
        var t = k === "" ? "" : I18n.tr(k)
        return (t !== "" && t !== k) ? t : I18n.tr(fallback)
    }

    // ---- Tray item menus (K23). The daemon names the item (runtime.ui.tray); its tree is fetched
    // once per open, as action data, and drawn by TrayMenu. A newer open supersedes an older fetch.
    readonly property string trayKey: trayWanted ? String(ui.tray || "") : ""
    property var trayTree: null
    property string trayErr: ""
    property int trayReq: 0
    onTrayKeyChanged: loadTray()
    function loadTray() {
        var req = ++trayReq
        trayTree = null
        trayErr = ""
        trayMenu.cursor = -1
        trayMenu.expanded = ({})
        if (trayKey === "") return
        Store.act("tray.menu", {id: trayKey}, function (done, err) {
            if (req !== stage.trayReq || stage.trayKey === "") return   // superseded, or closed meanwhile
            if (err) stage.trayErr = stage.errorText(err, "frontend.tray.failed")
            else stage.trayTree = done.data || ({children: []})
        })
    }
    // The item the menu belongs to (title and tooltip come from svc.tray), or an empty object.
    function trayItem(id) {
        var items = (Store.docs["svc.tray"] || ({})).items || []
        for (var i = 0; i < items.length; i++) if (items[i].id === id) return items[i]
        return ({})
    }
    // The tooltip without its first line (the title, already shown), one line for the heading below.
    function trayTipText(id) {
        var it = trayItem(id)
        return String(it.tooltip || "").split("\n").filter(function (l) { return l !== "" && l !== it.title }).join(" · ")
    }

    // ---- peeks (K35, I55, I67): the hover or focus peek of a bar item, drawn under a top bar, above a bottom bar, or beside a
    // side bar, aligned to the item, on the output the daemon names. Only while no card is open (the daemon removes a peek
    // when a panel opens). The peek is never focused: the keyboard stays where it was. Its content is the source's: a mod's
    // Peek.qml (ModLoader hands in its store), or the lines read here for a tray item and for the island.
    readonly property var peekReq: ui.peek || null
    readonly property string peekSourceId: peekReq && peekReq.source ? String(peekReq.source) : ""
    readonly property string peekOutput: peekReq && peekReq.output ? String(peekReq.output) : ""
    readonly property real peekX: peekReq && peekReq.x !== undefined ? Number(peekReq.x) : 0
    // The bar's edge, and for a side bar the item's y on it (PROTOCOL §8: absent is a top bar's peek).
    readonly property string peekEdge: peekReq && peekReq.edge ? String(peekReq.edge) : "top"
    readonly property real peekY: peekReq && peekReq.y !== undefined ? Number(peekReq.y) : 0
    readonly property string peekKind: peekKindOf(peekSourceId)
    readonly property var peekMod: peekKind === "mod" ? Mods.panelOf(peekSourceId) : null
    // Live: the source is one this shell can draw now (its mod is on and has the component, a tray item has text, the
    // island has a line for its face).
    readonly property bool peekAvailable: peekMod !== null
        ? Mods.qmlOf(modsDoc, "peek:" + peekMod.panel, peekMod.mod) !== "" : peekLinesOf(peekSourceId).length > 0
    // Asked for now: available, on this Stage's output, and on an enabled bar of any edge (I67: side bars too).
    readonly property bool peekWanted: peekAvailable && !open && bars.enabled && !!screen && screen.name === peekOutput
    // Held while the peek is asked for and while it fades out (I67): the Stage keeps the peek's output and place until the
    // fade is over. Set when a peek is wanted; cleared when the fade ends, or at once when there is no fade to play.
    property bool peekHeld: false
    readonly property bool peekLayout: peekHeld && !shown
    // What the peek shows is latched while it is wanted, so a peek fading out keeps its own source and place (the request is
    // gone by then). Each Binding follows the request only while the peek is wanted.
    property string shownSource: ""
    property string shownOutput: ""
    property string shownEdge: "top"
    property real shownX: 0
    property real shownY: 0
    Binding { target: stage; property: "shownSource"; value: stage.peekSourceId; when: stage.peekWanted; restoreMode: Binding.RestoreNone }
    Binding { target: stage; property: "shownOutput"; value: stage.peekOutput; when: stage.peekWanted; restoreMode: Binding.RestoreNone }
    Binding { target: stage; property: "shownEdge"; value: stage.peekEdge; when: stage.peekWanted; restoreMode: Binding.RestoreNone }
    Binding { target: stage; property: "shownX"; value: stage.peekX; when: stage.peekWanted; restoreMode: Binding.RestoreNone }
    Binding { target: stage; property: "shownY"; value: stage.peekY; when: stage.peekWanted; restoreMode: Binding.RestoreNone }
    readonly property string shownKind: peekKindOf(shownSource)
    readonly property var shownMod: shownKind === "mod" ? Mods.panelOf(shownSource) : null
    readonly property bool peekSide: shownEdge === "left" || shownEdge === "right"
    // The output the peek is on: the request's while it is available, the latched one while it fades out.
    readonly property string peekScreen: peekAvailable ? peekOutput : shownOutput
    readonly property int peekInset: Theme.barH + 4             // past a top or bottom bar, as BarConfig's insets
    readonly property int peekBarClear: Theme.barH + Theme.gap  // past a side bar
    readonly property int peekMaxW: screen
        ? Math.max(160, Math.min(400, screen.width - (peekSide ? peekBarClear : 0) - 2 * Theme.gap)) : 400
    // Kept a gap away from the output's edges, like the cards (lead review: a clamped peek touched the edge).
    readonly property int peekLeft: Math.max(Theme.gap, Math.min(shownX, (screen ? screen.width : 0) - peekCard.width - Theme.gap))
    readonly property int peekTop: Math.max(Theme.gap, Math.min(Math.round(shownY), (screen ? screen.height : 0) - peekCard.height - Theme.gap))
    readonly property int peekSlide: 6
    property real peekP: 0          // the fade in and out, 0..1
    property bool peekGate: false   // waiting for the first presented frame of the peek
    // Motion off (the theme's durations are 0, DESIGN-SYSTEM §9): the peek comes and goes at once, with no animation.
    readonly property bool peekInstant: Theme.quickMs <= 0
    function peekKindOf(src) {
        if (src.indexOf("tray:") === 0) return "tray"
        if (src.indexOf("island:") === 0) return "island"
        return Mods.panelOf(src) !== null ? "mod" : ""
    }
    // A tray item's lines: its title, then its tooltip lines (the title is not repeated).
    function trayPeek(src) {
        var it = trayItem(src.substring("tray:".length))
        var title = String(it.title || "")
        var out = title !== "" ? [title] : []
        String(it.tooltip || "").split("\n").forEach(function (l) { if (l !== "" && l !== title) out.push(l) })
        return out
    }
    // The island's line: the shown face's, as the daemon composed it. A transient face has none (as the Island).
    function islandPeek() {
        var doc = Store.docs["runtime.island.main"] || ({})
        var f = doc.face || "clock"
        if (["volume", "brightness", "power", "bluetooth"].indexOf(f) >= 0) return []
        var t = (doc.detail || ({}))[f]
        return t === undefined || t === null || String(t) === "" ? [] : [String(t)]
    }
    function peekLinesOf(src) {
        var k = peekKindOf(src)
        return k === "tray" ? trayPeek(src) : (k === "island" ? islandPeek() : [])
    }
    function screenNamed(name) {
        var s = Quickshell.screens
        for (var i = 0; i < s.length; i++) if (s[i].name === name) return s[i]
        return null
    }
    // The Stage is on the peek's output while the peek is asked for or fades out, and back on shell.qml's output once it has
    // gone: RestoreBinding hands the property back to shell.qml's binding. Not while a card is open: the card keeps its output.
    Binding {
        when: (stage.peekAvailable || stage.peekHeld) && !stage.open && stage.screenNamed(stage.peekScreen) !== null
        target: stage
        property: "screen"
        value: stage.screenNamed(stage.peekScreen)
        restoreMode: Binding.RestoreBinding
    }
    // Watched only while a peek of that kind is asked for (Ma).
    Watch { doc: "svc.tray"; active: stage.peekKind === "tray" }
    Watch { doc: "runtime.island.main"; active: stage.peekKind === "island" }
    // The fade in and out (DESIGN-SYSTEM §9: quick, interruptible; none under reduced motion). The fade in starts on the first
    // frame that shows the peek (peekGate); the fade out runs while the window is still mapped, and the Stage is idle at its end.
    NumberAnimation {
        id: peekAnim
        target: stage; property: "peekP"
        duration: Theme.quickMs
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve
        onFinished: if (stage.peekP <= 0 && !stage.peekWanted) stage.peekHeld = false
    }
    onPeekWantedChanged: {
        peekAnim.stop()
        if (peekWanted) {
            // A new peek comes at once and fades in from wherever the last one stood, even in the middle of a fade out.
            peekHeld = true
            if (peekInstant) { peekP = 1; peekGate = false }
            else peekGate = peekP < 1
        } else if (peekHeld && peekP > 0 && !peekInstant && !open) {
            // Gone: the fade out, with the latched place kept until it ends (peekAnim releases the hold then).
            peekGate = false
            peekAnim.from = peekP; peekAnim.to = 0; peekAnim.start()
        } else {
            // Gone at once: a card is open, motion is off, or nothing was drawn yet.
            peekHeld = false; peekP = 0; peekGate = false
        }
    }
    // The frame: the content and the card's padding, at most the output's width less a gap. The Stage anchors it (see
    // anchors). The pointer on it keeps it (Peeks.hold); a click dismisses it. Its content is loaded only while it is held (Ma).
    Rectangle {
        id: peekCard
        visible: stage.peekLayout
        width: Math.max(160, Math.min(stage.peekMaxW, peekLoader.implicitWidth + 2 * Theme.pad))
        height: peekLoader.implicitHeight + 2 * Theme.pad
        radius: Theme.rSm
        color: Theme.containerHigh
        // K62: with a pen in effect the pen draws the outline (1 px further in: the frame clips its children).
        border.width: peekPen.active ? 0 : (Theme.outlineW > 0 ? Theme.outlineW : 1)
        border.color: Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline
        clip: true
        Loader {
            id: peekPen
            z: 5
            anchors.fill: parent
            active: Theme.penOutline && peekCard.visible
            sourceComponent: PenOutline {
                radius: peekCard.radius
                inset: 1
                color: peekCard.border.color
                lineWidth: Theme.outlineW > 0 ? Theme.outlineW : 1
                seed: 0x9EE4
            }
        }
        opacity: stage.peekP
        // It slides in from its bar: down from a top bar, up from a bottom bar, out from a side bar.
        x: (stage.shownEdge === "left" ? -1 : (stage.shownEdge === "right" ? 1 : 0)) * stage.peekSlide * (1 - stage.peekP)
        y: (stage.peekSide ? 0 : (stage.shownEdge === "bottom" ? 1 : -1)) * stage.peekSlide * (1 - stage.peekP)
        HoverHandler { onHoveredChanged: hovered ? Peeks.hold() : Peeks.leave() }
        TapHandler { onTapped: Peeks.dismiss() }
        Loader {
            id: peekLoader
            x: Theme.pad
            y: Theme.pad
            active: stage.peekLayout
            sourceComponent: stage.shownKind === "mod" ? peekModView : (stage.shownKind === "" ? null : peekLinesView)
        }
    }
    Component {
        id: peekModView
        ModLoader { provide: stage.shownMod ? "peek:" + stage.shownMod.panel : ""; mod: stage.shownMod ? stage.shownMod.mod : "" }
    }
    Component {
        id: peekLinesView
        PeekLines { lines: stage.peekLinesOf(stage.shownSource); maxWidth: stage.peekMaxW - 2 * Theme.pad }
    }

    // ---- the island's one shape (W21, see the header). Everything here is in a top bar's frame ("local": y from the
    // screen edge the bar is on); for a bottom bar the shape is mirrored and the content placed from the Stage's bottom.
    readonly property var islandKinds: ["island", "modface", "media", "notifications", "clock", "volume", "brightness",
        "power", "bluetooth"]
    readonly property string outName: screen ? screen.name : ""
    // The pill's rect, read when the card opens and followed only while the shape is out: idle, a pill that grows under the
    // pointer must not touch the Stage at all (Ma; test-peek counts the Stage's commits per peek).
    property var pillGeom: null
    Binding {
        target: stage
        property: "pillGeom"
        value: IslandGeom.pillOf(stage.outName)
        when: stage.shown
        restoreMode: Binding.RestoreNone
    }
    readonly property bool morphMode: islandKinds.indexOf(contentKind) >= 0 && pillGeom !== null
        && (bars.atTop || bars.atBottom)
    readonly property bool flip: bars.atBottom
    // The window takes the morph's geometry (the bar's strip and the slack) only while the shape is out; idle, it keeps the
    // card's, so a peek coming and going costs no extra reconfigure (test-peek's reduced-motion frame budget).
    readonly property bool morphLayout: morphMode && shown
    // The pill at rest: its face's top from the screen edge (a bottom bar's face ends a keycap shadow above the edge).
    readonly property real pillW: pillGeom ? pillGeom.w : 120
    readonly property real pillH: pillGeom ? pillGeom.h : Theme.barH - 10
    readonly property real pillTop: (Theme.barH - pillH - Theme.shadowDy) / 2 + (flip ? Theme.shadowDy : 0)
    // The card's content sits where it always did: past the bar and 4 px (BarConfig's inset); the shape ends at its foot.
    readonly property real cardTop: Theme.barH + 4
    // The bar's groups float as blocks (a chrome with groups and a shadow of either kind: no strip under them, Bar.qml):
    // the card joins the island's own block (I115). Else the neck joins the card to the bar's strip.
    readonly property bool lifted: Theme.shadowDy > 0 || Theme.softR > 0
    readonly property bool joined: Theme.groups && lifted
    // An outlined chrome with no shadow draws the island as a box on the strip, with no fill of its own (Bar.qml).
    readonly property bool boxed: Theme.outlineW > 0 && !lifted
    readonly property real neckR: joined ? 0 : Theme.rLg
    // Room round the card for the springs' overshoot (soft-limited to 8 %, see soft()) and for a soft shadow.
    readonly property int slackX: 16 + Theme.softR
    readonly property int slackY: 40
    readonly property real morphW: 2 * Math.ceil(Math.max(card.width / 2 + neckR + slackX,
        Math.abs(pillGeom ? pillGeom.dx : 0) + pillW / 2 + 8))
    readonly property real morphH: Math.ceil(cardTop + card.height + Theme.shadowDy + slackY)
    // The springs' progress, 0 = the pill, 1 = the card: width and height apart (Capsule). `expanding` picks which leads.
    property real mw: 0
    property real mh: 0
    property bool expanding: true
    // Set on the first presented frame of the shape; the bar's pill is hidden while it is (one island on screen).
    property bool taken: false
    Binding {
        target: IslandGeom
        property: "takenOn"
        value: stage.outName
        when: stage.taken && stage.morphMode && !stage.handedToView
    }
    // A view with its own chrome (the phone) takes over from the shape once it is in: the shape dissolves into it and the
    // bar gets its pill back while the view stands; closing brings the shape back to fold into the pill.
    readonly property bool handedToView: ownChrome && contentP >= 0.99
    readonly property bool springing: stage.shown && !stage.gate && Theme.springOn
    Behavior on mw {
        enabled: stage.springing
        SpringAnimation {
            spring: Theme.spring * (stage.expanding ? 1.3 : 1.2)
            damping: Math.min(1, Theme.damping * (stage.expanding ? 1 : 1.25))
            epsilon: 0.002
        }
    }
    Behavior on mh {
        enabled: stage.springing
        SpringAnimation {
            spring: Theme.spring * (stage.expanding ? 1.0 : 1.6)
            damping: Math.min(1, Theme.damping * (stage.expanding ? 1.25 : 1))
            epsilon: 0.002
        }
    }
    // The open card turns into the island's (the quick card gave way to a face's view): it grows out of the pill now.
    onMorphModeChanged: {
        if (!morphMode) { taken = false; return }
        if (shown && open && !gate) { taken = true; expanding = true; mw = 1; mh = 1 }
    }
    // Folded back: the pill is handed back to the bar first, and the shape goes a moment later, so neither surface ever
    // shows no island.
    onMwChanged: checkFolded()
    onMhChanged: checkFolded()
    function checkFolded() {
        if (open || !shown || !morphMode || handBack.running) return
        if (mw <= 0.02 && mh <= 0.02) { taken = false; handBack.start() }
    }
    Timer {
        id: handBack
        interval: 80
        onTriggered: {
            if (stage.open) return
            stage.shown = false
            stage.mw = 0
            stage.mh = 0
        }
    }
    // Test only: the morph's state twice a second while the shape is out (KURASHI_STAGE_DEBUG=1).
    Timer {
        interval: 500
        repeat: true
        running: Quickshell.env("KURASHI_STAGE_DEBUG") === "1" && stage.shown && stage.morphMode
        onTriggered: console.log("stage-morph mw=" + stage.mw.toFixed(3) + " mh=" + stage.mh.toFixed(3) + " content=" + stage.contentP.toFixed(2)
            + " open=" + stage.open + " gate=" + stage.gate + " card=" + card.width + "x" + card.height + " win=" + stage.width + "x" + stage.height)
    }
    // A spring past its target is soft-limited (8 %), so the shape stays inside the Stage's slack; below 0 it is held.
    function soft(v) { return v > 1 ? 1 + Math.min((v - 1) * 0.6, 0.08) : Math.max(0, v) }
    function lerp(a, b, t) { return a + (b - a) * t }
    readonly property real ew: soft(mw)
    readonly property real eh: soft(mh)
    readonly property real tw: Math.max(0, Math.min(1, mw))
    readonly property real th: Math.max(0, Math.min(1, mh))
    readonly property real shapeW: lerp(pillW, card.width, ew)
    readonly property real shapeH: lerp(pillH, cardTop + card.height - pillTop, eh)
    readonly property real shapeCx: morphW / 2 + lerp(pillGeom ? pillGeom.dx : 0, 0, tw)
    // K61: how far the shape's body is from its place at rest, in output axes: its centre and its foot against the
    // card's (0 once grown), so the island's sheet comes out with the body as it grows.
    readonly property point shapeCarry: Qt.point(shapeCx - morphW / 2,
        (flip ? -1 : 1) * (bodyTop + bodyH - cardTop - card.height))
    // The pill's corners (square corners: radius.full 0) and its centre at rest.
    readonly property real pillR: Math.min(Theme.rFull, pillH / 2)
    readonly property real pillCx: morphW / 2 + (pillGeom ? pillGeom.dx : 0)
    // The body: the whole shape on a strip; in the joined topology what grows out from under the head (the pill), from
    // its foot to the card's rect. The view is cut to it.
    readonly property real bodyTop: joined ? lerp(pillTop + pillH, cardTop, eh) : pillTop
    readonly property real bodyH: joined ? Math.max(0, lerp(0, card.height, eh)) : shapeH
    // The shape's fill: the pill's at first, the card's once grown, at the panel's opacity (I114); a boxed pill has the
    // strip under it.
    readonly property color shapeFill: {
        var c = Qt.tint(boxed ? Theme.surface : Theme.containerHigh, Qt.alpha(Theme.container, tw))
        return Qt.alpha(c, Theme.panel.a)
    }
    // The view comes in once the shape has nearly grown (fade + 0.98 -> 1, <= 160 ms) and leaves first (90 ms).
    readonly property bool contentWanted: open && shown && !gate && mw > 0.72 && mh > 0.6
    property real contentP: 0
    onContentWantedChanged: contentP = contentWanted ? 1 : 0
    Behavior on contentP {
        enabled: stage.shown && Theme.quickMs > 0
        NumberAnimation { duration: stage.contentWanted ? 160 : 90; easing.type: Easing.OutCubic }
    }

    Item {
        id: shapeBox
        visible: stage.shown && stage.morphMode && opacity > 0
        opacity: stage.ownChrome ? 1 - stage.contentP : 1
        width: stage.morphW
        height: stage.morphH
        transform: Scale { yScale: stage.flip ? -1 : 1; origin.y: stage.morphH / 2 }
        // The soft chrome's shadow under the head and the body (static RectangularShadows that follow the springs).
        SoftShadow {
            visible: stage.joined
            x: stage.pillCx - stage.pillW / 2
            y: stage.pillTop
            width: stage.pillW
            height: stage.pillH
            radius: stage.pillR
            direction: stage.flip ? -1 : 1
        }
        SoftShadow {
            visible: shape.h > 1
            x: shape.x0
            y: shape.y0
            width: shape.w
            height: shape.h
            radius: Math.min(shape.rTop, shape.rBot)
            direction: stage.flip ? -1 : 1
        }
        MorphShape {
            id: shape
            visible: shapeBox.visible
            anchors.fill: parent
            joined: stage.joined
            hx0: stage.pillCx - stage.pillW / 2
            hy0: stage.pillTop
            hw: stage.pillW
            hh: stage.pillH
            hr: stage.pillR
            neckF: Theme.rLg / 2
            x0: stage.shapeCx - stage.shapeW / 2
            y0: stage.bodyTop
            w: stage.shapeW
            h: stage.bodyH
            rTop: stage.joined ? Theme.rLg : stage.lerp(stage.pillR, Theme.rLg, stage.th)
            rBot: stage.lerp(stage.pillR, Theme.rLg, stage.th)
            edgeY: Theme.barH
            neck: stage.neckR
            fill: stage.shapeFill
            ringScale: 0.5 + 0.5 * stage.tw
            flip: stage.flip
        }
        // The shape's fill as a mask for its relief (I168): the fill path alone, in white, drawn only into `shapeMask`'s
        // texture, which is redrawn when the path changes (while the shape morphs) and never at rest.
        Shape {
            id: maskShape
            visible: reliefBox.on
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillColor: "white"
                PathSvg { path: reliefBox.on ? shape.fillPath : "" }
            }
        }
        // Parked outside the window, as TileSheet's copies: a texture provider needs its paint node.
        ShaderEffectSource {
            id: shapeMask
            x: -100000
            width: parent.width
            height: parent.height
            sourceItem: reliefBox.on ? maskShape : null
            hideSource: true
            live: false
        }
        Connections {
            target: reliefBox.on ? shape : null
            function onFillPathChanged() { shapeMask.scheduleUpdate() }
        }
    }
    // K59, K61 (I168): the island's material — one relief over the shape's whole box, clipped to the shape's own fill path
    // (head, neck fillets and body; the outline and ring stay flat), under the views; with `texture.text` over them. The
    // head stays registered with the bar it sits in (no carry above its foot; on a strip, whose own relief shows through
    // the translucent fill, weighed by the fill's opacity so it is shaded about once); the body carries its sheet as it
    // grows (`shapeCarry`: the body's foot and centre against the card's at rest, 0 once grown). The sheet registers by
    // window pixel, so the Stage's mirror for a bottom bar does not move it.
    Item {
        id: reliefBox
        readonly property bool on: Theme.texShell && shape.visible && shape.w > 2 && shape.h > 2
        z: Theme.texText ? 2 : 0
        visible: on
        opacity: shapeBox.opacity
        width: stage.morphW
        height: stage.morphH
        transform: Scale { yScale: stage.flip ? -1 : 1; origin.y: stage.morphH / 2 }
        Loader {
            anchors.fill: parent
            active: reliefBox.on
            sourceComponent: Relief {
                anchors.fill: parent
                mask: shapeMask
                carry: stage.shapeCarry
                bandEdge: stage.joined ? shape.hy0 + shape.hh : shape.edgeY
                bandWeight: stage.joined ? 1 : Theme.panel.a
            }
        }
    }
    // The island's face, in the shape's head where the pill was (it moves to the card's centre as the shape widens).
    CompactFace {
        id: headFace
        active: stage.shown && stage.morphMode
        // Not visible while idle: its geometry follows the pill (hover), and a visible item that moves costs a frame (Ma).
        visible: active
        face: stage.pillGeom ? (stage.pillGeom.face || "clock") : "clock"
        animate: stage.shown
        opacity: shapeBox.opacity
        // Joined: the face stays in the head, the island's block; on a strip it rides the shape's centre.
        x: Math.round((stage.joined ? stage.pillCx : stage.shapeCx) - width / 2)
        y: stage.flip ? stage.morphH - stage.pillTop - stage.pillH : stage.pillTop
        width: Math.max(stage.pillW, wantW + 2 * Theme.pad)
        height: stage.pillH
    }

    // ---- card under the Island: the island's view or the quick card, session menu, or tray menu
    Rectangle {
        id: card
        visible: stage.shown
        // Media, the calendar and the quick settings card (docs/ux/quick-settings.md) need the wider card; a mod panel
        // asks for its card width (contract row 66); the session menu is as wide as its row of tiles; the rest keep 360 px.
        width: ["media", "clock", "quick", "power", "bluetooth"].indexOf(stage.contentKind) >= 0 ? 400
            : (stage.contentKind === "mod" ? stage.modCardWidth
            : (stage.contentKind === "session" ? Math.max(360, menu.implicitWidth + 2 * (Theme.pad + 4)) : 360))
        height: (stage.viewing ? col.implicitHeight
            : stage.contentKind === "session" ? menu.implicitHeight : trayCol.implicitHeight) + 2 * stage.cardPad
        // K28: a slot filling or emptying grows or shrinks the card smoothly. Off until the first frame has
        // shown (the reveal is the slide), so opening the card does not animate its height from the closed size.
        // Clipped, so a grown row is revealed by the card's edge rather than drawn over its margin.
        clip: true
        Behavior on height {
            enabled: stage.open && !stage.gate
            NumberAnimation { duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
        }
        // Slide, not fade: group opacity over a text-heavy card cost ~4 MiB of retained heap (K16).
        // The island's card (W21): the shape draws it; this holds the view where the grown shape will be, fading in after it.
        x: stage.morphMode ? Math.round((stage.morphW - width) / 2) : 0
        y: stage.morphMode ? (stage.flip ? stage.morphH - stage.cardTop - height : stage.cardTop)
            : -stage.slide * (1 - stage.p)   // above the surface edge = clipped away
        opacity: stage.morphMode ? stage.contentP : 1
        scale: stage.morphMode ? 0.98 + 0.02 * stage.contentP : 1
        transformOrigin: stage.flip ? Item.Bottom : Item.Top
        radius: Theme.rLg
        color: stage.morphMode || stage.ownChrome ? "transparent" : Theme.panel
        // K62: with a pen in effect the pen draws the card's outline (1 px further in: the card clips its children).
        border.width: stage.morphMode || stage.ownChrome || cardPen.active ? 0 : (Theme.outlineW > 0 ? Theme.outlineW : 1)
        border.color: Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline
        Loader {
            id: cardPen
            z: 5
            anchors.fill: parent
            active: Theme.penOutline && !stage.morphMode && !stage.ownChrome && card.visible
            sourceComponent: PenOutline {
                radius: card.radius
                inset: 1
                color: card.border.color
                lineWidth: Theme.outlineW > 0 ? Theme.outlineW : 1
                seed: 0x57A6E
            }
        }
        // K59: the card is a material area (its fill is the panel's); the relief lies under the views. Off while the
        // island morphs, where the shape draws the card.
        Loader {
            anchors.fill: parent
            anchors.margins: Theme.outlineW
            active: Theme.texShell && !Theme.texText && !stage.morphMode && !stage.ownChrome
            sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, card.radius - Theme.outlineW) }
        }
        // With `texture.text` the relief lies over the views too: their text and icons sink into the same sheet.
        Loader {
            z: 1
            anchors.fill: parent
            anchors.margins: Theme.outlineW
            active: Theme.texShell && Theme.texText && !stage.morphMode && !stage.ownChrome
            sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, card.radius - Theme.outlineW) }
        }
        // The Stage's one keyboard focus holder. The menus are driven from here and never take
        // focus themselves (a second holder would clear this flag for good). Esc closes whichever panel.
        focus: true
        Keys.onPressed: event => {
            if (stage.contentKind === "session" && menu.handleKey(event.key)) { event.accepted = true; return }
            if (stage.contentKind === "tray" && trayMenu.handleKey(event.key)) { event.accepted = true; return }
            if (event.key === Qt.Key_Escape) { Store.act("ui.close"); event.accepted = true }
        }

        // The island's view is shown only inside the shape (W21): while it grows or folds, what is past its edge is cut
        // away, so the view never spills out of the island.
        Item {
            id: reveal
            readonly property real shapeTop: stage.flip ? stage.morphH - stage.bodyTop - stage.bodyH : stage.bodyTop
            readonly property real cutTop: stage.morphMode ? Math.max(0, Math.min(card.height, shapeTop - card.y)) : 0
            readonly property real cutBottom: stage.morphMode
                ? Math.max(cutTop, Math.min(card.height, shapeTop + stage.bodyH - card.y)) : card.height
            readonly property real cutLeft: stage.morphMode
                ? Math.max(0, Math.min(card.width, stage.shapeCx - stage.shapeW / 2 - card.x)) : 0
            readonly property real cutRight: stage.morphMode
                ? Math.max(cutLeft, Math.min(card.width, stage.shapeCx + stage.shapeW / 2 - card.x)) : card.width
            x: cutLeft
            y: cutTop
            width: cutRight - cutLeft
            height: cutBottom - cutTop
            clip: stage.morphMode
        Item {
            id: inner
            x: -reveal.cutLeft
            y: -reveal.cutTop
            width: card.width
            height: card.height

        Column {
            id: col
            visible: stage.viewing
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: stage.cardPad }
            spacing: Theme.pad
            // Its height is the view's implicit one (an explicit binding to it loops in Qt).
            Loader {
                id: view
                width: col.width
                active: stage.shown && stage.viewing
                sourceComponent: stage.viewing ? stage.views[stage.contentKind] : null
            }
            // The one close action of the island and quick cards (Esc closes them too).
            KeyButton {
                visible: !stage.ownChrome
                label: I18n.tr("frontend.stage.close")
                primary: true
                side: 28
                onClicked: Store.act("ui.close")
            }
        }

        SessionMenu {
            id: menu
            visible: stage.contentKind === "session"
            active: stage.open && stage.contentKind === "session"
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.pad + 4 }
        }

        Column {
            id: trayCol
            visible: stage.contentKind === "tray"
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.pad + 4 }
            spacing: Theme.gap
            Text {
                width: trayCol.width
                elide: Text.ElideRight
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                font.family: Theme.fam(text, Theme.families)
                text: stage.trayItem(stage.trayKey).title || I18n.tr("frontend.tray.menu")
            }
            Text {
                visible: text !== ""
                width: trayCol.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: stage.trayTipText(stage.trayKey)
            }
            TrayMenu {
                id: trayMenu
                width: trayCol.width
                tree: stage.trayTree
                errText: stage.trayErr
                onChosen: item => {
                    Store.act("tray.menu_event", {id: stage.trayKey, item: item})
                    Store.act("ui.close")
                }
            }
        }
        }
        }
    }
}
