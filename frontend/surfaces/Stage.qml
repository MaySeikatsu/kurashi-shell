import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../core/mods.js" as Mods
import "../components"
import "../components/expanded"

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
PanelWindow {
    id: stage

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
    onWantedKindChanged: if (wantedKind !== "") contentKind = wantedKind
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

    // Only one vertical edge anchored -> the compositor centres the surface horizontally. A peek is anchored left
    // instead, at its own x (K35), on the bar's side of the output.
    anchors {
        top: peekLayout ? !bars.atBottom : (!bars.atBottom && !menuBeside)
        bottom: peekLayout ? bars.atBottom : (bars.atBottom || menuBeside)
        left: peekLayout || (menuBeside && bars.edge === "left")
        right: !peekLayout && aligned && (!bars.vertical || bars.edge === "right")
    }
    margins {
        top: bars.topInset
        bottom: menuBeside ? Theme.pad : bars.bottomInset
        left: peekLayout ? peekLeft : (menuBeside ? Theme.barH + Theme.gap : 0)
        right: aligned ? (menuBeside ? Theme.barH + Theme.gap : Theme.pad) : 0
    }
    implicitWidth: peekLayout ? peekCard.width : card.width
    implicitHeight: peekLayout ? peekCard.height : card.height
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "kurashi-stage"
    color: "transparent"
    mask: peekLayout ? peekRegion : (shown ? cardRegion : emptyRegion)
    BackgroundEffect.blurRegion: peekLayout ? peekRegion : (shown ? cardRegion : emptyRegion)
    Region { id: cardRegion; item: card }
    Region { id: peekRegion; item: peekCard }
    Region { id: emptyRegion }

    onOpenChanged: {
        if (open) {
            // Content first: a menu closed a moment ago must not show for a frame.
            contentKind = wantedKind === "" ? "island" : wantedKind
            Qt.callLater(function () { card.forceActiveFocus() })
            anim.stop()
            if (!shown) { p = 0; gate = true; shown = true }
            else { anim.from = p; anim.to = 1; anim.start() }
        } else if (shown) {
            gate = false
            anim.stop(); anim.from = p; anim.to = 0; anim.start()
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
            if (stage.gate) { stage.gate = false; anim.from = stage.p; anim.to = 1; anim.start() }
            if (stage.peekGate) { stage.peekGate = false; peekAnim.start() }
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

    // ---- peeks (K35, I55): the hover or focus peek of a bar item, drawn under the top bar or above the bottom bar, at the
    // item's x, on the output the daemon names. Only while no card is open (the daemon removes a peek when a panel opens).
    // The peek is never focused: the keyboard stays where it was. Its content is the source's: a mod's Peek.qml (ModLoader
    // hands in its store), or the lines read here for a tray item and for the island.
    readonly property var peekReq: ui.peek || null
    readonly property string peekSourceId: peekReq && peekReq.source ? String(peekReq.source) : ""
    readonly property string peekOutput: peekReq && peekReq.output ? String(peekReq.output) : ""
    readonly property real peekX: peekReq && peekReq.x !== undefined ? Number(peekReq.x) : 0
    readonly property string peekKind: peekKindOf(peekSourceId)
    readonly property var peekMod: peekKind === "mod" ? Mods.panelOf(peekSourceId) : null
    // Live: the source is one this shell can draw now (its mod is on and has the component, a tray item has text, the
    // island has a line for its face).
    readonly property bool peekAvailable: peekMod !== null
        ? Mods.qmlOf(modsDoc, "peek:" + peekMod.panel, peekMod.mod) !== "" : peekLinesOf(peekSourceId).length > 0
    // Drawn here: available, on this Stage's output, and on an enabled top or bottom bar (a side bar's peeks are not offered).
    readonly property bool peekWanted: peekAvailable && !open && bars.enabled && !bars.vertical && !!screen
        && screen.name === peekOutput
    readonly property bool peekLayout: peekWanted && !shown
    readonly property int peekMaxW: screen ? Math.max(160, Math.min(400, screen.width - 2 * Theme.gap)) : 400
    // Kept a gap away from the output's edges, like the cards (lead review: a clamped peek touched the edge).
    readonly property int peekLeft: Math.max(Theme.gap, Math.min(peekX, (screen ? screen.width : 0) - peekCard.width - Theme.gap))
    readonly property int peekSlide: 6
    property real peekP: 0          // the fade and slide in, 0..1
    property bool peekGate: false   // waiting for the first presented frame of the peek
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
    // The Stage is on the peek's output while the peek is asked for, and back on shell.qml's output once it has gone:
    // RestoreBinding hands the property back to shell.qml's binding. Not while a card is open: the card keeps its output.
    Binding {
        when: stage.peekAvailable && !stage.open && stage.screenNamed(stage.peekOutput) !== null
        target: stage
        property: "screen"
        value: stage.screenNamed(stage.peekOutput)
        restoreMode: Binding.RestoreBinding
    }
    // Watched only while a peek of that kind is asked for (Ma).
    Watch { doc: "svc.tray"; active: stage.peekKind === "tray" }
    Watch { doc: "runtime.island.main"; active: stage.peekKind === "island" }
    // The fade and slide in (DESIGN-SYSTEM §9: quick, and none under reduced motion), starting on the first frame that shows it.
    NumberAnimation {
        id: peekAnim
        target: stage; property: "peekP"; to: 1
        duration: Theme.quickMs
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve
    }
    onPeekWantedChanged: {
        peekAnim.stop()
        peekP = 0
        peekGate = peekWanted
    }
    // The frame: the content and the card's padding, at most the output's width less a gap. The Stage anchors it (see
    // anchors). The pointer on it keeps it (Peeks.hold); a click dismisses it. Its content is loaded only while it shows (Ma).
    Rectangle {
        id: peekCard
        visible: stage.peekWanted
        width: Math.max(160, Math.min(stage.peekMaxW, peekLoader.implicitWidth + 2 * Theme.pad))
        height: peekLoader.implicitHeight + 2 * Theme.pad
        radius: Theme.rSm
        color: Theme.containerHigh
        border.width: 1
        border.color: Theme.outline
        clip: true
        opacity: stage.peekP
        y: (bars.atBottom ? 1 : -1) * stage.peekSlide * (1 - stage.peekP)
        HoverHandler { onHoveredChanged: hovered ? Peeks.hold() : Peeks.leave() }
        TapHandler { onTapped: Peeks.dismiss() }
        Loader {
            id: peekLoader
            x: Theme.pad
            y: Theme.pad
            active: stage.peekWanted
            sourceComponent: stage.peekKind === "mod" ? peekModView : (stage.peekKind === "" ? null : peekLinesView)
        }
    }
    Component {
        id: peekModView
        ModLoader { provide: stage.peekMod ? "peek:" + stage.peekMod.panel : ""; mod: stage.peekMod ? stage.peekMod.mod : "" }
    }
    Component {
        id: peekLinesView
        PeekLines { lines: stage.peekLinesOf(stage.peekSourceId); maxWidth: stage.peekMaxW - 2 * Theme.pad }
    }

    // ---- card under the Island: the island's view or the quick card, session menu, or tray menu
    Rectangle {
        id: card
        visible: stage.shown
        // Media, the calendar and the quick settings card (docs/ux/quick-settings.md) need the wider card; a mod panel
        // asks for its card width (contract row 66); the rest keep 360 px.
        width: ["media", "clock", "quick", "power", "bluetooth"].indexOf(stage.contentKind) >= 0 ? 400
            : (stage.contentKind === "mod" ? stage.modCardWidth : 360)
        height: (stage.viewing ? col.implicitHeight
            : stage.contentKind === "session" ? menu.implicitHeight : trayCol.implicitHeight) + 2 * (Theme.pad + 4)
        // K28: a slot filling or emptying grows or shrinks the card smoothly. Off until the first frame has
        // shown (the reveal is the slide), so opening the card does not animate its height from the closed size.
        // Clipped, so a grown row is revealed by the card's edge rather than drawn over its margin.
        clip: true
        Behavior on height {
            enabled: stage.open && !stage.gate
            NumberAnimation { duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
        }
        // Slide, not fade: group opacity over a text-heavy card cost ~4 MiB of retained heap (K16).
        y: -stage.slide * (1 - stage.p)   // above the surface edge = clipped away
        radius: Theme.rLg
        color: Theme.container
        border.width: 1
        border.color: Theme.outline
        // The Stage's one keyboard focus holder. The menus are driven from here and never take
        // focus themselves (a second holder would clear this flag for good). Esc closes whichever panel.
        focus: true
        Keys.onPressed: event => {
            if (stage.contentKind === "session" && menu.handleKey(event.key)) { event.accepted = true; return }
            if (stage.contentKind === "tray" && trayMenu.handleKey(event.key)) { event.accepted = true; return }
            if (event.key === Qt.Key_Escape) { Store.act("ui.close"); event.accepted = true }
        }

        Column {
            id: col
            visible: stage.viewing
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.pad + 4 }
            spacing: Theme.pad
            // Its height is the view's implicit one (an explicit binding to it loops in Qt).
            Loader {
                id: view
                width: col.width
                active: stage.shown && stage.viewing
                sourceComponent: stage.viewing ? stage.views[stage.contentKind] : null
            }
            // The one close action of the island and quick cards (Esc closes them too).
            Button { label: I18n.tr("frontend.stage.close"); primary: true; onClicked: Store.act("ui.close") }
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
