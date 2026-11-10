import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../core"
import "../core/mods.js" as Mods
import "../components"
import "../components/expanded"
import "../components/island"
import "../components/sidebar"
import "../components/decor"
import "../components/motion"
import "../core/motion"
import "../components/bar/framegeom.js" as FG

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
// W34 (docs/ux/motion.md, one motion language): under a top or bottom bar every panel morphs that way — the quick card
// (the phone too), the session menu, a tray menu, a mod's panel and the hover peeks grow out of the bar widget they belong
// to (IslandGeom's origins; the session menu, which has none, out of the bar's centre under the pill) and fold back into
// it, their cards resting where they always did. The springs are MorphSprings (centre, width, foot; velocity kept across
// every retarget; calm settles, lively bounces with squash & stretch and a neck wobble, none cuts). Switching panels while
// one is open retargets the one shape (the view fades first, then the content swaps). The window is the box round origin
// and card (left-anchored, `boxL`), fitted when the shape comes out and only grown while it is out.
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
    // I128 (W36): while a polkit dialog is up (runtime.ui.polkit, K47 (5)) the Stage steps aside: no panel opens, no peek,
    // no keyboard focus. The daemon closes an open panel when the dialog comes up and refuses the Stage's panel and peek
    // actions while it is up (row 381, `ui.error.polkit`); these gates only cover the frame before its patch arrives.
    readonly property bool polkit: ui.polkit === true
    readonly property bool asked: want || quickWanted || modWanted
    readonly property bool open: asked && !polkit
    // K24: the island card shows the expanded view of the face the daemon latched when it opened. A core face
    // without one gets the generic card; a mod face loads its `island-face:<name>:expanded` (K28), or the generic card.
    // power and bluetooth open their quick settings pages, not the generic card (I44).
    readonly property var expandedFaces: ["media", "notifications", "clock", "volume", "brightness", "power", "bluetooth"]
    readonly property string islandKind: expandedFaces.indexOf(ui.face) >= 0 ? ui.face : (ui.face ? "modface" : "island")
    readonly property string wantedKind: sessionWanted ? "session" : (trayWanted ? "tray"
        : (quickWanted ? "quick" : (modWanted ? "mod" : (want ? islandKind : ""))))
    // The same, read from the document itself at the moment it is called (I192): `onOpenChanged` runs while the bindings
    // above may still hold the previous runtime.ui, and a stale "" made the generic view first and then the face's.
    function kindNow() {
        var u = Store.docs["runtime.ui"] || ({})
        if (u.panel === "session") return "session"
        if (u.panel === "tray") return "tray"
        if (u.panel === "quick") return "quick"
        var p = Mods.panelOf(u.panel)
        if (p !== null && Mods.qmlOf(modsDoc, "panel:" + p.panel, p.mod) !== "") return "mod"
        if (!want) return ""
        return expandedFaces.indexOf(u.face) >= 0 ? u.face : (u.face ? "modface" : "island")
    }
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
        if (ui.tray) shownTray = String(ui.tray)
    }
    // The tray item whose menu is (or was last) shown: its icon is where the menu folds back to (W34).
    property string shownTray: ""
    // Content the card shows. Latched while the card slides out, so a closing menu does not flash other content.
    property string contentKind: "island"
    // Not while the panel is being closed: runtime.ui loses its face a moment before shell.qml drops `want`, and the generic
    // card must not flash in the closing island (W21).
    // W34: switching panels while one is open (quick → session → tray, mod → mod, a face's view → quick) is a retarget:
    // the view fades out first, then the content swaps and the shape springs from where it is to the new card.
    onWantedKindChanged: {
        if (wantedKind === "" || (wantedKind === "island" && !ui.panel && ui.popup !== true)) return
        // I340: the bar module this card was opened from — pressed on this output just now — else none (a key, the CLI).
        var lp = IslandGeom.lastPress
        openedFrom = lp.output === outName && Date.now() - lp.t < 1500 ? lp.mid : ""
        // W59.9a (row 658): and where it was pressed (iris opens from there).
        openedPress = openedFrom !== "" ? lp : null
        if (shown && open && morphLayout && !gate && contentKind !== wantedKind && contentP > 0.01 && Theme.quickMs > 0) {
            pendingKind = wantedKind
            if (!swap.running) swap.start()
        } else {
            swap.stop()
            pendingKind = ""
            contentKind = wantedKind
        }
    }
    property string pendingKind: ""
    readonly property bool swapping: pendingKind !== ""
    // I340 (`bar.popups`, `bar.popups_other`): where a card a bar module opened comes out — under that module (`fromModule`:
    // an island view too then hangs from the module instead of growing out of the pill) or at the bar's centre (`toCentre`:
    // a panel too then comes out under the island, not under its widget). The island's own pill is always its own origin.
    property string openedFrom: ""
    property var openedPress: null
    function placeOf(mid) {
        var g = String(bars.valueOf("bar.popups", "module")) === "centre" ? "centre" : "module"
        var other = bars.valueOf("bar.popups_other", []) || []
        return other.indexOf(mid) >= 0 ? (g === "module" ? "centre" : "module") : g
    }
    readonly property bool fromModule: {
        var rev = IslandGeom.revision
        return openedFrom !== "" && openedFrom !== "island" && placeOf(openedFrom) === "module"
            && IslandGeom.rectOf(outName, "module:" + openedFrom) !== null
    }
    readonly property bool toCentre: openedFrom !== "" && openedFrom !== "island" && placeOf(openedFrom) === "centre"
    Timer {
        id: swap
        interval: 90
        onTriggered: if (stage.pendingKind !== "") {
            // A view not made yet keeps the card's present size meanwhile (I192): the shape stays out, never folds back.
            stage.bridgeSize = { w: card.width, h: card.height }
            stage.contentKind = stage.pendingKind
            stage.pendingKind = ""
        }
    }
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
    // around it; the island's shape (or the slide) still brings it in. Known per kind before the view is made (I192: the
    // view loads asynchronously, and the card's padding must not jump when it arrives).
    readonly property bool ownChrome: viewing && (["quick", "power", "bluetooth"].indexOf(contentKind) >= 0
        || (view.item !== null && view.item.ownChrome === true))
    // I192 (W36): the view is made asynchronously, so the patch that opens a panel is answered by a frame at once. The
    // card takes the size that view had the last time it was shown (per kind; a mod panel and a mod face's view per
    // name) until the view is ready, so the shape grows straight to it; only a view's very first open holds the growth
    // until it is made. The content fades in only once it is there.
    readonly property bool viewReady: !viewing || view.status === Loader.Ready
    readonly property string sizeKey: contentKind === "mod" ? "mod:" + shownPanelMod + ":" + shownPanel
        : (contentKind === "modface" ? shownFaceView : contentKind)
    property var sizeCache: ({})
    property var bridgeSize: null
    readonly property var cachedSize: viewing ? (sizeCache[sizeKey] || bridgeSize) : null
    readonly property bool sizeKnown: viewReady || cachedSize !== null
    // (Written in place, with no notify: the size is read at the next open, which `viewing` and `sizeKey` already re-evaluate.
    // A new object here is a loop through `cachedSize` and the card's size, which Qt 6.12 reports.)
    function recordSize() {
        if (!viewing || !viewReady || !open || gate || !reached) return
        var c = sizeCache[sizeKey]
        if (c && c.w === card.width && c.h === card.height) return
        sizeCache[sizeKey] = { w: card.width, h: card.height }
    }
    readonly property int cardPad: ownChrome ? 0 : Theme.pad + 4
    // ---- W53.0b (K80): the title bar, as the daemon says (`runtime.ui.title`, absent: none — the style draws no title
    // bar, `title_bar.buttons` is off, or no card is open). Its height is the style's (`decor.title.height`, W53.0a).
    readonly property var titleDoc: ui.title || null
    // W53.4 (lead review): quick settings drawn as a flyout (`[decor] quick.frame = flyout`) are their own chrome — a menu
    // extra's drop-down, Control Centre, 11's flyout — and get no caption or window frame round them.
    readonly property bool flyoutView: ["quick", "power", "bluetooth"].indexOf(contentKind) >= 0
        && Theme.decor("quick.frame", "phone") === "flyout"
    readonly property bool titled: titleDoc !== null && contentKind !== "" && !flyoutView
    // A flyout that hangs from its bar (`[decor] flyout.hang`, Mac OS X's menu extras) meets the bar's edge (BarConfig's
    // 4 px inset left out; the flyout leaves out its own shadow room on that side).
    readonly property bool hangs: flyoutView && Theme.decor("flyout.hang", false) === true
    readonly property int titleH: titled ? Math.round(Theme.tok("decor.title.height", 28)) : 0
    // Row 595: a captioned card's window frame, px (`decor.border.width`; 0 = today's 1 px outline).
    readonly property int frameW: titled ? Math.max(0, Math.round(Theme.decor("border.width", 0))) : 0
    // Maximize = full screen: the largest card the output has room for, under (or over) its bar.
    readonly property bool full: titled && titleDoc.full === true
    // S21 (the user: the caption's maximize "does not follow the animation style"): growing to full screen moves on the
    // profile's opening curve and back on its closing one (the card's size, and on a morph the shape with it), instead of
    // jumping. `resizing` holds while that move runs; minimize closes the card, in its close form, as `ui.close` does.
    property bool resizing: false
    // (on a morph the springs already carry the shape on the profile's curves)
    onFullChanged: if (open && shown && !gate && Theme.springOn && !morphMode) { resizing = true; resizeEnd.restart() }
    Timer { id: resizeEnd; interval: Math.max(1, stage.full ? Theme.openMs : Theme.closeMs) + 32; onTriggered: stage.resizing = false }
    readonly property int fullW: screen ? screen.width - 2 * Theme.pad : 720
    readonly property int fullH: screen ? screen.height - Theme.barH - bars.topInset - bars.bottomInset - 3 * Theme.pad : 600
    readonly property string cardTitle: {
        if (contentKind === "tray") return moduleKey !== "" ? moduleMenu.title : (trayItem(trayKey).title || I18n.tr("frontend.tray.menu"))
        if (contentKind === "quick" || contentKind === "power" || contentKind === "bluetooth") return I18n.tr("layout.module.quick")
        if (contentKind === "mod") return shownPanelMod
        if (contentKind === "session") return I18n.tr("styles.title.session")
        if (contentKind === "modface" || contentKind === "island") return ui.face ? I18n.tr("config.face." + ui.face) : ""
        return I18n.tr("config.face." + contentKind)
    }
    Component {
        id: plainTitle
        Item {
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                anchors { left: parent.left; leftMargin: Theme.pad + 4; right: keys.left; rightMargin: Theme.gap
                          verticalCenter: parent.verticalCenter }
                text: stage.cardTitle
                elide: Text.ElideRight
                color: Theme.fg
                font.pixelSize: Theme.fsCaption
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
            }
            Row {
                id: keys
                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                spacing: 2
                Repeater {
                    model: stage.titleDoc ? stage.titleDoc.buttons : []
                    delegate: IconButton {
                        required property var modelData
                        activeFocusOnTab: false
                        icon: modelData.id === "close" ? "close" : modelData.id === "minimize" ? "minimize"
                            : (stage.full ? "fullscreen_exit" : "fullscreen")
                        glyph: modelData.id === "close" ? "×" : modelData.id === "minimize" ? "–" : "□"
                        a11y: I18n.tr(modelData.action === "app_menu" ? "styles.title.app_menu"
                            : modelData.id === "maximize" && stage.full ? "styles.title.restore" : "styles.title." + modelData.id)
                        onClicked: Store.act("ui.title", { button: modelData.id })
                    }
                }
            }
        }
    }
    // A mod panel's root may declare `property int cardWidth` (the card's outer width, contract row 66): the card
    // takes it within 360..1100 px and the output's width (the handwriting mod's drawing board is the wide one); the panel
    // gets the card's content width.
    readonly property var modPanel: contentKind === "mod" && view.item ? view.item.item : null
    readonly property int modCardWidth: {
        var want = modPanel && modPanel.cardWidth > 0 ? modPanel.cardWidth : 360
        var room = screen ? screen.width - 2 * Theme.pad : 720
        return Math.max(360, Math.min(want, 1100, room))
    }
    // W53.5: the width the view asks its card for (`cardWant`, ≥ 0), e.g. the calendar's grid in a wide pixel face.
    readonly property int viewWant: view.item && view.item.cardWant !== undefined ? view.item.cardWant : 0
    Component { id: genericView; GenericView {} }
    Component { id: mediaView; MediaView {} }
    Component { id: notificationsView; NotificationsView {} }
    Component { id: clockView; ClockView {} }
    Component { id: volumeView; VolumeView {} }
    Component { id: brightnessView; BrightnessView {} }
    Component { id: quickView; QuickPanel { fromBottom: stage.flip } }
    // The power and bluetooth faces' expanded views are the quick settings pages (I44): the card opens on that page.
    Component { id: powerView; QuickPanel { startPage: "power"; fromBottom: stage.flip } }
    Component { id: bluetoothView; QuickPanel { startPage: "bluetooth"; fromBottom: stage.flip } }
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
    // (a module's menu, I408, hangs from its module where the bar is a row)
    readonly property bool aligned: contentKind === "tray" && (!moduleMenuShown || bars.vertical || besideAt !== null)
    readonly property bool menuBeside: aligned && (bars.vertical || besideAt !== null)
    // A module on a side edge: the rect it reports (`side:<id>`), and the card stands beside it.
    readonly property var besideAt: {
        var rev = IslandGeom.revision
        if (!moduleMenuShown || !(shown || open)) return null
        return IslandGeom.rectOf(outName, "side:" + shownTray.substring("module:".length))
    }
    readonly property string besideEdge: besideAt !== null && besideAt.edge !== "" ? besideAt.edge : bars.edge

    readonly property int slide: 12     // px the card travels while revealing
    // The reveal's progress 0..1 where the card does not grow out of a bar (a side bar, a look whose cards stand apart),
    // on today's curve (the enter curve over `standard`; a stepped look's own staircases) — a Driver since K83 (row 655),
    // so KURASHI_MOTION_SCRUB holds it too.
    readonly property real p: pDrv.value
    property bool gate: false           // waiting for the first presented frame
    property bool shown: false          // card is on screen (opening, open or closing)

    // Only one vertical edge anchored -> the compositor centres the surface horizontally. A peek is anchored to the side of
    // its own bar instead (K35, I67): at its own x under a top bar or above a bottom bar, at its own y beside a side bar.
    // W34: while a shape morphs under a top or bottom bar the window is the box round its origin and its card (`boxL`,
    // from the output's left edge), so it is anchored to the left with that margin, as a peek is.
    anchors {
        top: placed || (peekLayout ? shownEdge !== "bottom" : (morphLayout ? !flip : (!bars.atBottom && !menuBeside) || besideAt !== null))
        bottom: !placed && (peekLayout ? shownEdge === "bottom" : (morphLayout ? flip : ((bars.atBottom || menuBeside) && besideAt === null)))
        left: placed || (peekLayout ? shownEdge !== "right" : (morphLayout || (menuBeside && besideEdge === "left")))
        right: !placed && (peekLayout ? shownEdge === "right" : (!morphLayout && aligned && (!menuBeside || besideEdge === "right")))
    }
    margins {
        top: placed ? placedY - placedRoom : peekLayout ? (shownEdge === "top" ? (peekMorph ? 0 : peekInset) : (peekSide ? peekTop : 0))
            : (morphLayout ? 0 : (besideAt !== null
                ? Math.round(Math.max(Theme.pad, Math.min((stage.screen ? stage.screen.height : 1080) - card.height - Theme.pad, besideAt.y + besideAt.h / 2 - card.height / 2)))
                : bars.topInset - (hangs ? 4 : 0)))
        bottom: peekLayout ? (shownEdge === "bottom" ? (peekMorph ? 0 : peekInset) : 0)
            : (morphLayout ? 0 : (menuBeside ? Theme.pad : bars.bottomInset - (hangs ? 4 : 0)))
        left: placed ? placedX - placedRoom : peekLayout ? (shownEdge === "left" ? peekBarClear : (shownEdge === "right" ? 0 : (peekMorph ? peekBoxL : peekLeft)))
            : (morphLayout ? boxL : (menuBeside ? bars.insetOf(besideEdge) + Theme.barH + Theme.gap : 0))
        right: peekLayout ? (shownEdge === "right" ? peekBarClear : 0)
            : (morphLayout ? 0 : (aligned ? (menuBeside ? bars.insetOf(besideEdge) + Theme.barH + Theme.gap : Theme.pad) : 0))
    }
    implicitWidth: peekLayout ? (peekMorph ? peekBoxR - peekBoxL : peekCard.width) : (morphLayout ? morphW : card.width + 2 * placedRoom)
    implicitHeight: peekLayout ? (peekMorph ? peekBoxH : peekCard.height) : (morphLayout ? morphH : card.height + 2 * placedRoom)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open && !polkit ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "kurashi-stage"
    color: "transparent"
    mask: peekLayout ? peekRegion : (shown ? cardRegion : emptyRegion)
    // Behind the card as drawn: a morphing card's body follows the springs every frame (the blur never stands ahead of
    // the shape, I295, and a grown card is blurred at rest, I296); the head and the neck's fillets stay unblurred.
    BackgroundEffect.blurRegion: !Theme.blur ? emptyRegion
        : peekLayout ? (peekMorph ? (peekShapeBox.visible && !peekSf ? peekShapeBlur : emptyRegion) : peekBlur) : (!shown ? emptyRegion : (morphMode ? (shapeBox.visible && formBlurs && !cardHost.sheetBlurOff ? shapeBlur : emptyRegion) : (run.busy && run.mode === "shape" || cardHost.sheetBlurOff ? emptyRegion : cardBlur)))
    // K83: a shape form that fades its card in (stamp) or draws only an outline keeps the blur off until the card stands
    // (a blurred box before its card would show); an iris blurs inside its circle (shapeBlur's ellipse).
    readonly property bool formBlurs: !sf || sf.below >= 0.999
    Region { id: cardRegion; item: card }
    Region { id: peekRegion; item: peekCard }
    // (rounded as the cards are drawn: a square region showed the blur past their corners, I276)
    Region { id: cardBlur; item: card; radius: card.radius }
    Region { id: peekBlur; item: peekCard; radius: peekCard.radius }
    // A morphing peek grows from its widget's group: behind its body as drawn, never its card's box ahead of it (I295).
    Region {
        id: peekShapeBlur
        x: peekShape.x0
        y: stage.peekFlip ? stage.peekBoxH - peekShape.y0 - peekShape.h : peekShape.y0
        width: peekShape.w
        height: peekShape.h
        radius: Theme.rSm
    }
    // I309: never over the bar's row — niri fills a layer's blur region with the blurred wallpaper over the layers under
    // it, so a card's head across the bar showed the wallpaper there (blur, translucency, line or flat chrome: the head is
    // see-through over the strip, I160); the bar blurs its strip itself.
    readonly property real blurTop: Math.max(bodyTop, barEdgeY)
    readonly property real blurH: Math.max(0, bodyTop + bodyH - blurTop)
    Region {
        id: shapeBlur
        x: stage.shapeCx - stage.shapeW / 2
        y: stage.flip ? stage.morphH - stage.blurTop - stage.blurH : stage.blurTop
        width: stage.shapeW
        height: stage.blurH
        topLeftRadius: stage.flip ? shape.rBot : shape.rTop
        topRightRadius: stage.flip ? shape.rBot : shape.rTop
        bottomLeftRadius: stage.flip ? shape.rTop : shape.rBot
        bottomRightRadius: stage.flip ? shape.rTop : shape.rBot
        // (K83, iris: only inside the circle; otherwise an empty union, so the region is exactly today's)
        Region {
            readonly property bool on: stage.sf !== null && stage.sf.irisR >= 0
            readonly property real r: on ? stage.sf.irisR : 0
            intersection: on ? Intersection.Intersect : Intersection.Combine
            shape: RegionShape.Ellipse
            x: on ? Math.round(stage.sf.irisX - r) : 0
            y: on ? Math.round((stage.flip ? stage.morphH - stage.sf.irisY : stage.sf.irisY) - r) : 0
            width: Math.round(2 * r)
            height: Math.round(2 * r)
        }
    }
    Region { id: emptyRegion }

    onOpenChanged: {
        if (open) {
            // Content first: a menu closed a moment ago must not show for a frame.
            bridgeSize = null
            swap.stop()
            pendingKind = ""
            var k = kindNow()
            contentKind = k === "" ? "island" : k
            pillGeom = IslandGeom.pillOf(outName)
            Qt.callLater(function () { card.forceActiveFocus() })
            handBack.stop()
            if (morphMode) {
                // The shape starts as its origin (no spring yet) and grows from the first presented frame on; reopened
                // while it folds back, it grows again from where it is, with its velocity (the targets move, MorphSprings).
                if (!shown) {
                    pDrv.snap(1); gate = true; shown = true
                    fitBox(true)
                    springs.place(originCx, closedW, closedFoot)
                }
            } else if (!shown) { pDrv.snap(0); gate = true; shown = true }
            else runP(1)
        } else if (shown) {
            gate = false
            reached = false
            swap.stop()
            pendingKind = ""
            if (morphMode) {
                if (debugLog) console.log("stage-morph close " + contentKind + " t0=" + Date.now())
                Qt.callLater(checkFolded)
            } else runP(0)
        }
    }
    // W53.5: a stepped look (`motion.kind = stepped`) opens on its own staircase and time and folds on its close one; the
    // card itself grows out of its middle (below), so the content's Entrance stays still.
    readonly property bool stepped: Theme.motionKind === "stepped"
    readonly property var enterCurve: ({ kind: "cubic", ms: Theme.stdMs, points: Theme.enterCurve })
    Driver {
        id: pDrv
        curves: stage.stepped ? ({ open: { kind: "cubic", ms: Theme.openMs, points: Theme.openCurve },
                                   close: { kind: "cubic", ms: Theme.closeMs, points: Theme.closeCurve } })
            : ({ open: stage.enterCurve, close: stage.enterCurve })
        keepVelocity: false
        // (a shape form still folding the card ends it itself: `run.landed`)
        onLanded: if (stage.p <= 0 && !stage.open && !run.busy) stage.shown = false
    }
    // Run the reveal to `t` from where it stands (a new travel also when `to` is there already: a reopen mid-fold).
    function runP(t) { if (pDrv.to !== t) pDrv.to = t; else pDrv.go() }
    Connections {
        target: card.Window.window
        function onFrameSwapped() {
            if (stage.gate) {
                // The shape starts at its origin, read now (runtime.ui may name the panel a moment after the Stage
                // opened), and grows from here on.
                if (stage.morphMode) {
                    springs.place(stage.originCx, stage.closedW, stage.closedFoot)
                    if (stage.debugLog) console.log("stage-morph open " + stage.contentKind + " origin=" + Math.round(stage.origin.x) + ","
                        + Math.round(stage.origin.w) + "," + stage.origin.kind + " t0=" + Date.now() + " " + stage.firstLog())
                }
                stage.gate = false
                if (stage.morphMode) stage.taken = stage.headMode
                else stage.runP(1)
            }
            if (stage.peekGate) {
                stage.peekGate = false
                // W34: a peek on a top or bottom bar grows out of its widget first; its lines fade in once it has.
                // Its start is read now: the latched place may have followed the request after the peek was asked for.
                if (stage.peekMorph) {
                    if (!stage.peekOut && Math.abs(peekSprings.h - stage.peekE) < 1) peekSprings.place(stage.peekOriginCx, stage.peekOriginW, stage.peekE)
                    stage.peekOut = true
                    stage.peekFadeIn()
                }
                else { peekAnim.from = stage.peekP; peekAnim.to = 1; peekAnim.start() }
            }
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
    // I408: `module:<id>` names a module's own menu instead of a tray item: the same panel and TrayMenu, its tree from the
    // schema (ModuleMenu) rather than from the item.
    readonly property string moduleKey: trayKey.indexOf("module:") === 0 ? trayKey.substring("module:".length) : ""
    readonly property bool moduleMenuShown: shownTray.indexOf("module:") === 0
    ModuleMenu { id: moduleMenu; module: stage.moduleKey; bars: bars }
    property var trayTree: null
    property string trayErr: ""
    property int trayReq: 0
    onTrayKeyChanged: loadTray()
    function loadTray() {
        var req = ++trayReq
        // Closed: the menu folds back with the tree it showed (W34: no "loading" flash while it goes).
        if (trayKey === "") return
        // (from trayKey itself: `moduleKey` may not have followed it yet when this runs)
        if (trayKey.indexOf("module:") === 0) { trayMenu.cursor = -1; trayMenu.expanded = ({}); trayTree = null; trayErr = ""; return }
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
        ? Mods.qmlOf(modsDoc, "peek:" + peekMod.panel, peekMod.mod) !== ""
        : peekKind === "preview" || peekLinesOf(peekSourceId).length > 0
    // Asked for now: available, on this Stage's output, and on an enabled bar of any edge (I67: side bars too).
    readonly property bool peekWanted: peekAvailable && !open && !polkit && bars.enabled && !!screen && screen.name === peekOutput
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
    // Row 512: past the bar the peek's source stands in (the request's edge) and that bar's inset (a floating bar's band +
    // gap, K71): under a top bar, above a bottom bar (as BarConfig's insets), beside a side bar.
    readonly property var peekBar: IslandGeom.barOf(peekScreen, shownEdge)
    readonly property int peekBarInset: peekBar ? peekBar.inset : bars.insetOf(shownEdge)
    readonly property int peekInset: peekBarInset + Theme.barH + 4
    readonly property int peekBarClear: peekBarInset + Theme.barH + Theme.gap
    readonly property int peekMaxW: screen
        ? Math.max(160, Math.min(shownKind === "preview" ? 640 : 400, screen.width - (peekSide ? peekBarClear : 0) - 2 * Theme.gap)) : 400
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
        if (src.indexOf("window:") === 0 || src.indexOf("workspace:") === 0) return "preview"
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
    Watch { doc: "svc.previews"; active: stage.peekKind === "preview" }
    Watch { doc: "svc.workspaces"; active: stage.peekKind === "preview" }
    // The fade in and out (DESIGN-SYSTEM §9: quick, interruptible; none under reduced motion). The fade in starts on the first
    // frame that shows the peek (peekGate); the fade out runs while the window is still mapped, and the Stage is idle at its end.
    NumberAnimation {
        id: peekAnim
        target: stage; property: "peekP"
        duration: Theme.quickMs
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve
        onFinished: if (stage.peekP <= 0 && !stage.peekWanted && !stage.peekMorph) stage.peekHeld = false
    }
    onPeekWantedChanged: {
        peekAnim.stop()
        if (peekWanted) {
            // A new peek comes at once and fades in from wherever the last one stood, even in the middle of a fade out.
            var fresh = !peekHeld
            peekHeld = true
            if (peekInstant) { peekP = 1; peekGate = false }
            else peekGate = peekP < 1
            // W34: a fresh peek's shape starts at its widget; one that is still folding grows again from where it is.
            if (fresh && peekMorph) { peekOut = false; peekSprings.place(peekOriginCx, peekOriginW, peekE) }
            else if (peekMorph && !peekGate) peekOut = true
        } else if (peekHeld && peekP > 0 && !peekInstant && !open) {
            // Gone: the fade out, with the latched place kept until it ends (peekAnim releases the hold then; a peek's
            // shape folds back into its widget, which releases it, W34).
            peekGate = false
            peekAnim.from = peekP; peekAnim.to = 0; peekAnim.start()
            peekOut = false
        } else if (peekHeld && peekMorph && peekOut && !open) {
            peekGate = false
            peekOut = false
        } else {
            // Gone at once: a card is open, motion is off, or nothing was drawn yet.
            peekHeld = false; peekP = 0; peekGate = false
        }
    }
    // ---- W34: the peek's shape. On a top or bottom bar (springs on) a peek grows out of its widget's box (the request's x
    // and w) as the panels do — headless, out of the strip's edge or the widget's block — and its lines fade in once it
    // has; it folds back into the widget when it goes. The window covers the bar's strip, the widget and the card.
    // (A look's tooltip part draws a free balloon: no morph out of the bar, W53 row 591.)
    readonly property bool peekMorph: peekLayout && !peekSide && Theme.springOn && !peekBalloon
    TooltipStyle { id: peekTip }
    // I457 (session 27, user): on a top or bottom bar every peek grows out of the bar and joins it as a module's menu
    // does — a preview, the island's, a tray item's, a mod's — in a look with a tooltip part too. The look's balloon
    // stays where a peek cannot join: beside a side bar, and with the springs off.
    readonly property bool peekBalloon: peekTip.has && (peekSide || !Theme.springOn)
    // K98, as a card: in dynamic a peek near the frame's corner runs into it instead of standing a few px beside it.
    readonly property bool peekDynamic: peekMorph && !joined && Theme.decor("surface.join", true) !== false
        && FG.edgeOf(outLay, peekFlip ? "bottom" : "top").draw === "dynamic"
    readonly property bool peekMergesL: peekDynamic && peekBoxL + peekShape.x0 < holeL + mergeRoom
    readonly property bool peekMergesR: peekDynamic && !peekMergesL && peekBoxL + peekShape.x0 + peekShape.w > holeR - mergeRoom
    // A peek with nothing to say (its lines empty: the timer's while none runs) draws nothing — no empty frame (I259).
    readonly property bool peekEmpty: {
        var l = peekLoader.item
        var v = l && l.item !== undefined ? l.item : l
        return !!v && v.lines !== undefined && v.lines !== null && v.lines.length === 0
    }
    property real shownW: 0
    Binding { target: stage; property: "shownW"; value: stage.peekReq && stage.peekReq.w !== undefined ? Number(stage.peekReq.w) : 0; when: stage.peekWanted; restoreMode: Binding.RestoreNone }
    readonly property bool peekFlip: shownEdge === "bottom"
    readonly property real peekEdgeY: peekBarInset + Theme.barH
    readonly property real peekE: joined ? peekBarInset + (peekFlip ? Theme.barH - 4 + Theme.shadowDy / 2 : Theme.barH - 4 - Theme.shadowDy / 2) : peekEdgeY
    readonly property real peekOriginW: Math.max(8, shownW - 6)
    readonly property real peekOriginCx: shownX + shownW / 2
    readonly property int peekSlackX: 16 + Theme.softR
    readonly property real peekBoxL: Math.max(0, Math.floor(Math.min(shownX, peekLeft) - Theme.rLg - peekSlackX))
    readonly property real peekBoxR: Math.ceil(Math.max(shownX + shownW, peekLeft + peekCard.width) + Theme.rLg + peekSlackX)
    readonly property real peekBoxH: Math.ceil(peekInset + peekCard.height + Theme.shadowDy + 24)
    property bool peekOut: false
    MorphSprings {
        id: peekSprings
        stiffness: 2
        on: Theme.springOn && stage.peekHeld && !(peekRun.formed && (peekRun.busy || !stage.peekOut))
        expanding: stage.peekOut
        cxTo: stage.peekOut ? stage.peekLeft + peekCard.width / 2 : stage.peekOriginCx
        wTo: stage.peekOut ? peekCard.width : stage.peekOriginW
        hTo: stage.peekOut ? stage.peekInset + peekCard.height : stage.peekE
    }
    // ---- K83 (W59.3): the peek's form (`peek`, on the `fast` curve: a peek is a glance). `grow` and today's forms keep its
    // springs; expand, iris, stamp and outline draw its shape from one progress, as the cards' (SurfaceForm).
    SurfaceForm {
        id: peekRun
        surface: "peek"
        role: "fast"
        want: stage.peekOut && stage.peekMorph
        hold: !peekSprings.settled && Math.abs(peekSprings.h - stage.peekE) > 1 && Math.abs(peekSprings.h - stage.peekInset - peekCard.height) > 1
        fromCx: stage.peekOriginCx - stage.peekBoxL
        fromW: stage.peekOriginW
        fromTop: stage.peekBarInset + 4
        fromFoot: stage.peekE
        fromR: Theme.rSm
        toCx: stage.peekLeft + peekCard.width / 2 - stage.peekBoxL
        toW: peekCard.width
        toTop: stage.peekInset
        toFoot: stage.peekInset + peekCard.height
        toR: Theme.rSm
        edgeY: stage.peekEdgeY
        // Folded back in its form: the peek is gone.
        onLanded: at => { if (at <= 0 && !stage.peekOut) { peekAnim.stop(); stage.peekP = 0; stage.peekHeld = false } }
    }
    onPeekHeldChanged: if (!peekHeld) peekRun.reset()
    readonly property QtObject peekSf: peekRun.mode === "shape" && peekRun.busy ? peekRun.shape : null
    readonly property bool peekNear: peekSprings.pw > 0.9 && peekSprings.ph > 0.6 && peekSprings.pcx > 0.9
    onPeekNearChanged: peekFadeIn()
    function peekFadeIn() {
        if (!peekMorph || !peekNear || !peekOut || !peekWanted || peekP >= 1 || peekAnim.running && peekAnim.to === 1) return
        peekAnim.stop(); peekAnim.from = peekP; peekAnim.to = 1; peekAnim.start()
    }
    // Folded back into the widget: the peek is gone (the Stage is idle at its end).
    Connections {
        target: peekSprings
        function onHChanged() {
            if (peekRun.formed && (peekRun.busy || peekRun.p > 0)) return
            if (stage.peekMorph && !stage.peekOut && !stage.peekWanted && Math.abs(peekSprings.h - stage.peekE) <= 1
                    && Math.abs(peekSprings.w - stage.peekOriginW) <= 3) {
                peekAnim.stop(); stage.peekP = 0; stage.peekHeld = false
            }
        }
    }
    readonly property real peekGrow: peekSf ? peekSf.grow : clamp01((peekSprings.hOut - peekE) / Math.max(1, peekInset + peekCard.height - peekE))
    readonly property real peekShapeW: peekSf ? peekSf.w * peekSf.sx : Math.max(0, peekSprings.wOut * (1 - peekSprings.squeeze))
    readonly property real peekShapeCx: peekSf ? peekSf.cx : peekSprings.cxOut - peekBoxL
    readonly property real peekFoot: peekSf ? peekEdgeY + (peekSf.foot - peekEdgeY) * peekSf.sy : peekSprings.hOut
    readonly property real peekBodyTop0: joined ? lerp(peekE, peekInset, peekGrow) : peekEdgeY
    readonly property real peekBodyTop: peekSf && peekBodyTop0 > peekEdgeY ? peekEdgeY + (peekBodyTop0 - peekEdgeY) * peekSf.sy : peekBodyTop0
    readonly property real peekNeckRoom: Math.max(0, peekShapeW / 2 - Theme.rSm - 8)
    // As the panels' neck: under the widget's group, as near the body's centre as the group's flat foot allows.
    readonly property var peekHome: {
        var rev = IslandGeom.revision
        if (!joined || !peekMorph) return null
        var keys = ["group:right", "group:workspaces", "group:tasks"]
        for (var i = 0; i < keys.length; i++) {
            var g = IslandGeom.rectOf(peekScreen, keys[i])
            if (g && peekOriginCx >= g.x && peekOriginCx <= g.x + g.w) return g
        }
        return null
    }
    readonly property real peekNeckLo: peekHome ? peekHome.x + Math.min(Theme.rFull, (Theme.barH - 8) / 2) + Theme.rSm + 8 - peekBoxL : peekOriginCx - peekBoxL
    readonly property real peekNeckHi: peekHome ? Math.max(peekNeckLo, peekHome.x + peekHome.w - Math.min(Theme.rFull, (Theme.barH - 8) / 2) - Theme.rSm - 8 - peekBoxL) : peekNeckLo
    readonly property real peekNeckWant: Math.max(peekNeckLo, Math.min(peekNeckHi, peekShapeCx))
    readonly property real peekNeckCx: Math.max(peekShapeCx - peekNeckRoom, Math.min(peekShapeCx + peekNeckRoom, peekNeckWant))
    // K83 (W59.3): the peek's card-level form host (a sheet form, W59.4, captures the whole peek: shape and lines).
    FormHost {
        id: peekHost
        surface: "peek"
        width: stage.peekBoxR - stage.peekBoxL
        height: stage.peekBoxH
        edge: stage.peekFlip ? "bottom" : "top"
        origin: Qt.rect(stage.peekOriginCx - stage.peekOriginW / 2 - stage.peekBoxL,
            stage.peekFlip ? stage.peekBoxH - stage.peekE : stage.peekBarInset + 4,
            stage.peekOriginW, Math.max(1, stage.peekE - stage.peekBarInset - 4))
        direction: peekRun.dir
        progress: peekRun.sheet ? peekRun.p : 1
        visible: !peekRun.sheet || peekRun.p > 0
    Item {
        id: peekForm
        width: stage.peekBoxR - stage.peekBoxL
        height: stage.peekBoxH
        // (the peek's lines are inside too: an expand cuts them at its foot, an iris shows them through its circle)
        layer.enabled: stage.peekSf !== null && stage.peekMorph
        layer.effect: FormMask {
            form: peekRun.shape
            keep: stage.peekEdgeY - (Theme.outlineW > 0 || stage.joined ? 0 : 1)
            flipped: stage.peekFlip
            cut: peekRun.form === "expand"
        }
    Item {
        id: peekShapeBox
        visible: stage.peekMorph && !stage.peekEmpty
        width: stage.peekBoxR - stage.peekBoxL
        height: stage.peekBoxH
        transform: Scale { yScale: stage.peekFlip ? -1 : 1; origin.y: stage.peekBoxH / 2 }
        SoftShadow {
            visible: peekShape.h > 1
            x: peekShape.x0
            y: peekShape.y0
            width: peekShape.w
            height: peekShape.h
            radius: Theme.rSm
            amount: 0.6
            direction: stage.peekFlip ? -1 : 1
        }
        MorphShape {
            id: peekShape
            visible: peekShapeBox.visible
            anchors.fill: parent
            joined: stage.joined
            headless: true
            // (the join's radii are the cards': one fillet everywhere a surface meets the bar, user, session 27)
            neckF: Theme.rJoin
            neckCx: stage.peekNeckCx
            attach: stage.clamp01(1 - Math.abs(stage.peekNeckCx - stage.peekNeckWant) / 32)
            neckScale: stage.peekSf ? 1 : peekSprings.neckScale
            stretch: stage.peekSf ? stage.peekSf.neck : 1
            x0: stage.peekShapeCx - stage.peekShapeW / 2
            y0: stage.peekBodyTop
            w: stage.peekShapeW
            h: Math.max(0, stage.peekFoot - stage.peekBodyTop)
            rTop: Theme.rSm
            rBot: Math.min(Theme.rLg, Math.max(Theme.rSm, w / 4))
            edgeY: stage.joined ? stage.peekE : stage.peekEdgeY
            neck: stage.joined ? 0 : Theme.rJoin
            // (I277: the peek is the bar's sheet, as the card it grows out of; a look's tooltip fill, W53)
            fill: stage.peekBalloon ? peekTip.fill(Theme.surfaceAlpha) : Theme.surfaceAlpha
            edgeL: stage.peekMergesL ? stage.holeL - stage.peekBoxL : -1e6
            edgeR: stage.peekMergesR ? stage.holeR - stage.peekBoxL : 1e6
            ringScale: 0.5
            flip: stage.peekFlip
        }
        // The peek's material (K59, I277): the relief clipped to the shape's fill path, as the island's card has it
        // (I168); the mask is redrawn only when the path changes.
        Shape {
            id: peekMaskShape
            visible: peekRelief.on
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillColor: "white"
                PathSvg { path: peekRelief.on ? peekShape.fillPath : "" }
            }
        }
        StillCopy {
            id: peekMask
            x: -100000
            width: parent.width
            height: parent.height
            sourceItem: peekRelief.on ? peekMaskShape : null
            hideSource: true
        }
        Connections {
            target: peekRelief.on ? peekShape : null
            function onFillPathChanged() { peekMask.scheduleUpdate() }
        }
        Loader {
            id: peekRelief
            readonly property bool on: Theme.texShell && peekShape.visible && peekShape.w > 2 && peekShape.h > 2
            anchors.fill: parent
            active: on
            sourceComponent: Relief { anchors.fill: parent; mask: peekMask; bandEdge: peekShape.edgeY; bandWeight: 1 }
        }
    }

    // The frame: the content and the card's padding, at most the output's width less a gap. The Stage anchors it (see
    // anchors). The pointer on it keeps it (Peeks.hold); a click dismisses it. Its content is loaded only while it is held (Ma).
    RoundBox {
        id: peekCard
        visible: stage.peekLayout
        width: Math.max(160, Math.min(stage.peekMaxW, peekLoader.implicitWidth + 2 * Theme.pad))
        height: peekLoader.implicitHeight + 2 * Theme.pad
        radius: Theme.rSm
        color: stage.peekMorph || stage.peekBalloon ? "transparent" : peekTip.fill(Theme.surfaceAlpha)
        // K62: with a pen in effect the pen draws the outline (1 px further in: the frame clips its children).
        border.width: peekPen.active || stage.peekMorph || stage.peekBalloon ? 0 : (Theme.outlineW > 0 ? Theme.outlineW : 1)
        border.color: Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline
        clip: true
        Loader {
            id: peekPen
            z: 5
            anchors.fill: parent
            active: Theme.penOutline && peekCard.visible && !stage.peekMorph
            sourceComponent: PenOutline {
                radius: peekCard.radius
                inset: 1
                color: peekCard.border.color
                lineWidth: Theme.outlineW > 0 ? Theme.outlineW : 1
                seed: 0x9EE4
            }
        }
        // (nothing drawn for an empty peek, I259; its loader stays to learn when there are lines again)
        // (K83: a shape form shows the lines as it says: through its mask, scaled with it, after the outline)
        opacity: stage.peekEmpty ? 0 : (stage.peekSf ? stage.peekSf.content : stage.peekP)
        transform: Scale {
            origin.x: stage.peekShapeCx - peekCard.x
            origin.y: (stage.peekFlip ? stage.peekBoxH - stage.peekEdgeY : stage.peekEdgeY) - peekCard.y
            xScale: stage.peekSf ? stage.peekSf.sx : 1
            yScale: stage.peekSf ? stage.peekSf.sy : 1
        }
        // It slides in from its bar: down from a top bar, up from a bottom bar, out from a side bar.
        x: stage.peekMorph ? stage.peekLeft - stage.peekBoxL
            : (stage.shownEdge === "left" ? -1 : (stage.shownEdge === "right" ? 1 : 0)) * stage.peekSlide * (1 - stage.peekP)
        y: stage.peekMorph ? (stage.peekFlip ? stage.peekBoxH - stage.peekInset - height : stage.peekInset)
            : (stage.peekSide ? 0 : (stage.shownEdge === "bottom" ? 1 : -1)) * stage.peekSlide * (1 - stage.peekP)
        // The bar's material on a free peek too (K59, I277).
        Loader {
            anchors.fill: parent
            anchors.margins: Theme.outlineW
            active: Theme.texShell && peekCard.visible && !stage.peekMorph && !stage.peekBalloon
            sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, peekCard.radius - Theme.outlineW) }
        }
        // The look's tooltip part under the lines (W53, row 591; TooltipBase), its tail toward the bar.
        Loader {
            anchors.fill: parent
            active: stage.peekBalloon && peekCard.visible
            source: active ? peekTip.part : ""
            onLoaded: item.tailSide = Qt.binding(function () { return stage.shownEdge })
        }
        HoverHandler { onHoveredChanged: hovered ? Peeks.hold() : Peeks.leave() }
        TapHandler { onTapped: Peeks.dismiss() }
        Loader {
            id: peekLoader
            x: Theme.pad
            y: Theme.pad
            active: stage.peekLayout
            sourceComponent: stage.shownKind === "mod" ? peekModView
                : stage.shownKind === "preview" ? peekPreviewView : (stage.shownKind === "" ? null : peekLinesView)
        }
    }
    }
    }
    OutlineRects {
        width: stage.peekBoxR - stage.peekBoxL
        height: stage.peekBoxH
        rects: stage.peekSf && stage.peekSf.outline ? stage.peekSf.rects : []
        transform: Scale { yScale: stage.peekFlip ? -1 : 1; origin.y: stage.peekBoxH / 2 }
    }
    Component {
        id: peekModView
        ModLoader { provide: stage.shownMod ? "peek:" + stage.shownMod.panel : ""; mod: stage.shownMod ? stage.shownMod.mod : "" }
    }
    Component {
        id: peekPreviewView
        PreviewPeek {
            source: stage.shownSource
            maxWidth: stage.peekMaxW - 2 * Theme.pad
            fg: stage.peekBalloon ? peekTip.ink(Theme.fg) : Theme.fg
            dim: stage.peekBalloon ? peekTip.ink(Theme.dim) : Theme.dim
        }
    }
    Component {
        id: peekLinesView
        PeekLines {
            lines: stage.peekLinesOf(stage.shownSource)
            maxWidth: stage.peekMaxW - 2 * Theme.pad
            fg: stage.peekBalloon ? peekTip.ink(Theme.fg) : Theme.fg
            dim: stage.peekBalloon ? peekTip.ink(Theme.dim) : Theme.dim
        }
    }

    // ---- the one shape (W21, W34; see the header). Everything here is in a top bar's frame ("local": y from the screen
    // edge the bar is on; for a bottom bar the shape is mirrored and the content placed from the Stage's bottom) and, along
    // the bar, in the output's px ("out": x from the output's left edge) until it is placed in the window (`boxL`).
    // W34 (docs/ux/motion.md): every panel of a top or bottom bar grows out of its origin — the island's views out of the
    // pill (the head: the pill is taken, `headMode`), the quick card, the tray menu and a mod's panel out of the bar widget
    // that opened them (IslandGeom's origins), the session menu (no widget) out of the bar's centre under the pill — and
    // folds back into it. Headless origins stay drawn in the bar: the shape grows out of the strip's edge under them, or,
    // where the groups float as blocks, out of the widget's block by a neck that lets go once the card has travelled away.
    readonly property var islandKinds: ["island", "modface", "media", "notifications", "clock", "volume", "brightness",
        "power", "bluetooth"]
    readonly property var panelKinds: ["quick", "session", "tray", "mod"]
    readonly property string outName: screen ? screen.name : ""
    readonly property real outW: screen ? screen.width : 1920
    // The pill's rect, read when the card opens and followed only while the shape is out: idle, a pill that grows under the
    // pointer must not touch the Stage at all (Ma; test-peek counts the Stage's commits per peek).
    property var pillGeom: null
    Binding {
        target: stage
        property: "pillGeom"
        // (`shown` read here so the value is taken afresh when the shape comes out: the pill's place is read from the items,
        // which no binding follows — a value kept from before would be stale, e.g. after the bar turned floating.)
        value: stage.shown ? IslandGeom.pillOf(stage.outName) : null
        when: stage.shown
        restoreMode: Binding.RestoreNone
    }
    readonly property bool headMode: islandKinds.indexOf(contentKind) >= 0 && pillGeom !== null && !fromModule
    // Row 512 (K71: a bar on each edge, floating or docked): the bar the shape grows from — the island's own bar for its
    // views (`pillOf().edge`), the bar of the widget a panel grew out of (`rectOf().edge`), else the island's bar, else
    // "the bar" (BarConfig) — and that bar's inset (a floating bar's band + gap). The local frame below counts y from that
    // bar's screen edge, so everything that stands on the bar adds `barInset`.
    readonly property var originRect: {
        var rev = IslandGeom.revision
        if (!(shown || open) || headMode || originKey === "") return null
        var r = IslandGeom.rectOf(outName, originKey)
        if (r === null && contentKind === "mod") r = IslandGeom.rectOf(outName, "mod:" + shownPanelMod + ":")
        return r
    }
    readonly property string morphEdge: headMode ? pillGeom.edge
        : (originRect !== null && originRect.edge !== "" ? originRect.edge : (pillGeom !== null ? pillGeom.edge : bars.edge))
    readonly property var morphBar: IslandGeom.barOf(outName, morphEdge)
    readonly property real barInset: morphBar ? morphBar.inset : bars.insetOf(morphEdge)
    // W53.5 (`[decor] surface.join = false`): a look whose cards stand apart from the bar never morphs.
    // K102: a mod's panel may stand on the screen instead of under the bar, by its setting `panel_place`. A card apart: it does
    // not morph, it keeps the elevation's room round it, and it stands clear of the bars and bands.
    readonly property string panelPlace: contentKind === "mod" && shownPanelMod !== ""
        ? String(bars.valueOf("mods." + shownPanelMod + ".panel_place", "opened")) : "opened"
    readonly property bool placed: panelPlace !== "opened" && !peekLayout
    readonly property int placedRoom: placed ? Theme.elevReach(3) : 0
    readonly property real placedX: {
        var w = card.width, band = outLay && outLay.frame && outLay.frame.band ? outLay.frame.band : ({})
        var L = Math.max(sideClear("left"), (band.left || 0) + Theme.gap), R = outW - Math.max(sideClear("right"), (band.right || 0) + Theme.gap)
        var p = panelPlace
        var x = p === "left" || p === "top_left" || p === "bottom_left" ? L
            : p === "right" || p === "top_right" || p === "bottom_right" ? R - w : (outW - w) / 2
        return Math.round(Math.max(L, Math.min(R - w, x)))
    }
    readonly property real placedY: {
        var h = card.height, H = screen ? screen.height : 1080, band = outLay && outLay.frame && outLay.frame.band ? outLay.frame.band : ({})
        var T = Math.max(bars.topInset, (band.top || 0) + Theme.gap), B = H - Math.max(bars.bottomEdgeInset, (band.bottom || 0) + Theme.gap)
        var p = panelPlace
        var y = p === "top" || p === "top_left" || p === "top_right" ? T
            : p === "bottom" || p === "bottom_left" || p === "bottom_right" ? B - h : (H - h) / 2
        return Math.round(Math.max(T, Math.min(Math.max(T, B - h), y)))
    }
    readonly property bool morphMode: !placed && Theme.decor("surface.join", true) !== false
        && (morphEdge === "top" || morphEdge === "bottom") && (morphBar !== null || bars.hasBar(morphEdge)) && besideAt === null
        && (headMode || panelKinds.indexOf(contentKind) >= 0 || fromModule)
    readonly property bool flip: morphEdge === "bottom"
    // The window takes the morph's geometry (the box, the bar's strip and the slack) only while the shape is out; idle, it
    // keeps the card's, so a peek coming and going costs no extra reconfigure (test-peek's reduced-motion frame budget).
    readonly property bool morphLayout: morphMode && shown
    readonly property bool debugLog: Quickshell.env("KURASHI_STAGE_DEBUG") === "1"
    // The pill at rest: its face's top from the screen edge (a bottom bar's face ends a keycap shadow above the edge).
    readonly property real pillW: pillGeom ? pillGeom.w : 120
    readonly property real pillH: pillGeom ? pillGeom.h : Theme.barH - 10
    readonly property real pillTop: barInset + (Theme.barH - pillH - Theme.shadowDy) / 2 + (flip ? Theme.shadowDy : 0)
    readonly property real pillOutCx: outW / 2 + (pillGeom ? pillGeom.dx : 0)
    // The bar's inner edge (local): where a strip ends and a headless shape grows out of it.
    readonly property real barEdgeY: barInset + Theme.barH
    // The card's content sits where it always did: past the bar and 4 px (BarConfig's inset); the shape ends at its foot.
    readonly property real cardTop: barEdgeY + 4
    // The bar's groups float as blocks (a chrome with groups and a shadow of either kind: no strip under them, Bar.qml):
    // the card joins the island's own block (I115), or a widget's block. Else the neck joins the card to the bar's strip.
    readonly property bool lifted: Theme.shadowDy > 0 || Theme.softR > 0
    readonly property bool joined: Theme.groups && lifted
    // An outlined chrome with no shadow draws the island as a box on the strip, with no fill of its own (Bar.qml).
    readonly property bool boxed: Theme.outlineW > 0 && !lifted
    readonly property real neckR: joined ? 0 : Theme.rJoin

    // The origin (out x, width; `e`: the line the shape hangs from, local). A widget's drawn square is 3 px in from its
    // box (QuickButton, TrayIcon); one not on this output (or none: the session menu) gives the pill, else the bar's centre.
    // A group's block, and the pill, end their face at a fixed place in the bar (Bar.qml's Group, Island's pill).
    readonly property real groupFoot: barInset + (flip ? Theme.barH - 4 + Theme.shadowDy / 2 : Theme.barH - 4 - Theme.shadowDy / 2)
    // (W70: the quick card a control's module opened comes out under that module, I340's `module:<id>`, not the button)
    readonly property string ownKey: contentKind === "quick" ? (openedFrom !== "" && openedFrom !== "quick" ? "" : "quick")
        : (contentKind === "tray" ? (moduleMenuShown ? shownTray : "tray:" + shownTray)
        : (contentKind === "mod" ? "mod:" + shownPanelMod + ":" + shownPanel.substring("panel:".length) : ""))
    // (a panel's own widget is the finer origin — a tray icon, not the whole tray; I340 the module's box else, or none
    // when its cards come out at the centre)
    readonly property string originKey: toCentre ? "" : (ownKey !== "" ? ownKey : (fromModule ? "module:" + openedFrom : ""))
    readonly property var origin: {
        if (!shown || headMode) return { x: pillOutCx - pillW / 2, w: pillW, e: pillTop + pillH, kind: "pill" }
        var r = originRect
        if (r !== null) return { x: r.x + 3, w: Math.max(8, r.w - 6), e: joined ? groupFoot : barEdgeY, kind: "widget",
                                 r: r.r >= 0 ? r.r : Theme.rSm }
        if (pillGeom !== null) return { x: pillOutCx - pillW / 2, w: pillW, e: joined ? pillTop + pillH : barEdgeY, kind: "pill" }
        return { x: outW / 2 - 40, w: 80, e: joined ? groupFoot : barEdgeY, kind: "centre" }
    }
    readonly property real originCx: origin.x + origin.w / 2
    // The origin's corner radius (W59.9a: liquid flows from it, a headless shape's corners start at it): the pill's, a
    // widget's own (IslandGeom), else a bar widget's.
    readonly property real originR: headMode || origin.kind === "pill" ? pillR : (origin.r !== undefined ? origin.r : Theme.rSm)
    // W59.9a (row 658): the press that opened the card, in the shape's frame (x in the window, y local); NaN: none.
    readonly property point pressAt: {
        var rev = IslandGeom.revision
        var q = shown && morphMode && openedPress ? IslandGeom.pressOf(openedPress) : null
        if (!q || !screen) return Qt.point(NaN, NaN)
        return Qt.point(q.x - boxL, flip ? screen.height - q.y : q.y)
    }
    // The shape closed: the pill (head), or a sliver at the line it hangs from.
    readonly property real closedW: origin.w
    readonly property real closedFoot: headMode ? pillTop + pillH : origin.e
    // The card at rest (W36): a panel that grew out of a bar widget (quick settings, a tray menu, a mod's panel) rests
    // under that widget, centred on it and kept Theme.pad inside the output — the container transform: the card is the
    // button grown, and its neck stays on the button's block where the groups float. The island's views and the session
    // menu (no widget) rest centred under the pill. A tray menu without its icon on this output keeps the tray's end.
    readonly property bool restsUnder: (panelKinds.indexOf(contentKind) >= 0 || fromModule) && origin.kind === "widget"
    // Session 15: kept inside what stands on the output's sides — the frame's band and its inner corner, a side bar —
    // not over them (a quick card under the bar's end lay on the right band and its fillet).
    readonly property var outLay: ShellLayout.of(screen ? screen.name : "")
    function sideClear(e) {
        var ed = FG.edgeOf(outLay, e), r = FG.band(outLay, e) > 0 || FG.docked(outLay, e)
            ? Math.max(0, Math.round((outLay.frame || {}).radius || 0)) : 0
        var bar = ed.bar === true && ed.visibility !== "hidden" ? Math.max(0, ed.inset || 0) + Theme.barH : 0
        return FG.band(outLay, e) + bar + Math.max(Theme.pad, r)
    }
    readonly property real clearL: sideClear("left")
    readonly property real clearR: sideClear("right")
    // I428, dynamic: a card under a widget near the output's side has no room for a fillet there, so it merges with what stands
    // there instead of keeping clear of it: flush on the band, a side bar or the screen's edge (Caelestia's popouts).
    readonly property bool dynamicEdge: morphMode && !joined && !headMode
        && FG.edgeOf(outLay, flip ? "bottom" : "top").draw === "dynamic"
    readonly property real holeL: FG.holeSide(outLay, "left", Theme.barH)
    readonly property real holeR: outW - FG.holeSide(outLay, "right", Theme.barH)
    readonly property real wantX: originCx - card.width / 2
    readonly property real mergeRoom: 2 * neckR + Theme.pad
    readonly property bool mergesL: dynamicEdge && restsUnder && wantX < holeL + mergeRoom
    readonly property bool mergesR: dynamicEdge && (restsUnder || aligned) && !mergesL && (aligned || wantX + card.width > holeR - mergeRoom)
    readonly property real cardOutX: mergesL ? holeL : mergesR ? holeR - card.width : restsUnder
        ? Math.round(Math.max(clearL, Math.min(outW - clearR - card.width, originCx - card.width / 2)))
        : (aligned ? outW - clearR - card.width : Math.round((outW - card.width) / 2))
    readonly property real cardFoot: cardTop + card.height

    // The box the window covers along the bar (out px) and its height: the origin and the card with the neck's and the
    // springs' slack. It only grows while the shape is out (a retarget adds the new card to it, never a resize mid-morph
    // that would cut the shape), and is fitted anew when the shape comes out.
    // The springs' room past origin and card: the width's soft-limited overshoot and the landing's bulge on each side, the
    // centre's overshoot past its travel (MorphSprings.cap, .squash), the neck's fillets and the soft shadow.
    // (I435: and the elevation's own reach, or the window cuts the card's shadow off in a straight line.)
    readonly property int slackX: 16 + Math.max(Theme.softR, Theme.elevReach(3))
        + Math.ceil(card.width * (springs.cap + springs.squash) / 2 + Math.abs(cardOutX + card.width / 2 - originCx) * springs.cap)
    readonly property int slackY: Math.max(40, Theme.elevReach(3))
    // I386: a card with a title bar can go full screen, so its window takes the output's width from the start. Widening it
    // then moves the layout at once but the window one configure later: the shape lay outside the window, and the card
    // vanished for two frames. (Its height grows from a fixed top, which moves nothing.)
    readonly property real needL: titled ? 0 : Math.floor(Math.min(origin.x, cardOutX) - neckR - slackX)
    readonly property real needR: titled ? outW : Math.ceil(Math.max(origin.x + origin.w, cardOutX + card.width) + neckR + slackX)
    readonly property real needH: Math.ceil(cardFoot + Theme.shadowDy + slackY)
    property real boxL: 0
    property real boxR: 0
    property real boxH: 0
    onNeedLChanged: fitBox(false)
    onNeedRChanged: fitBox(false)
    onNeedHChanged: fitBox(false)
    function fitBox(reset) {
        if (!morphMode) return
        var l = Math.max(0, needL), r = Math.min(outW, needR)
        if (reset || !shown) { boxL = l; boxR = r; boxH = needH; return }
        if (l < boxL) boxL = l
        if (r > boxR) boxR = r
        // A card that grows while it is out (a view filling in) grows the box in steps, not every frame.
        if (needH > boxH) boxH = needH + 48
    }
    // I435: a translucent card that hangs from the bar has the rule left out under it and the sheet's shadow cut.
    CardJoin {
        output: stage.screen ? stage.screen.name : ""
        side: "stage"
        on: stage.dynamicEdge && stage.open && Theme.tok("color.surface_alpha", 1) < 0.999
        readonly property real top: stage.flip ? stage.outH - stage.cardFoot : stage.barEdgeY
        readonly property real foot: stage.flip ? stage.outH - stage.barEdgeY : stage.cardFoot
        spans: {
            var l = [{ edge: stage.morphEdge, from: stage.cardOutX - (stage.mergesL ? 0 : Theme.rJoin),
                       to: stage.cardOutX + card.width + (stage.mergesR ? 0 : Theme.rJoin) }]
            if (stage.mergesL) l.push({ edge: "left", from: top, to: foot + Theme.rJoin })
            if (stage.mergesR) l.push({ edge: "right", from: top, to: foot + Theme.rJoin })
            return l
        }
        box: Qt.rect(stage.cardOutX, top, card.width, foot - top)
    }
    readonly property real morphW: Math.max(1, boxR - boxL)
    readonly property real morphH: boxH

    // The springs (MorphSprings): the shape's centre along the bar, its width and its foot, towards the card while the
    // panel is open and has shown its first frame, else towards the origin.
    // A view's first open holds the growth until the view is made (I192: else the size it had last time).
    readonly property bool extended: shown && !gate && (open || contentP > 0.4) && sizeKnown
    // K83 (W59.3): while a shape or sheet form moves the card (`run`), the springs stand at its rest place (they snap: the
    // form draws the shape), and once it is in they take over again, so a retarget to another panel still morphs. Folding
    // in a form, they stand at the origin (the shape that is left when the form has gone: the pill).
    readonly property bool formHolds: run.formed && (run.busy || !open)
    // S21 (the user: "opens fully, then jumps to a smaller width and back"): a form that has landed open hands the card to
    // the springs AT the card's rest — they stood still at the origin while the form drew it, and would grow it again.
    // (later: the springs come on in the same change and would restart from the spans they held)
    onFormHoldsChanged: if (!formHolds && open && run.formed) Qt.callLater(springs.snap)
    MorphSprings {
        id: springs
        on: Theme.springOn && stage.shown && !stage.formHolds
        expanding: stage.extended
        cxTo: stage.extended ? stage.cardOutX + card.width / 2 : stage.originCx
        wTo: stage.extended ? card.width : stage.closedW
        hTo: stage.extended ? stage.cardFoot : stage.closedFoot
    }
    // ---- K83 (W59.3, docs/ux/motion-engine.md §5–§7): the card's form. The island's views (D3: the pill is origin and
    // hinge) are the `island` class, the rest `panel` (quick, session, tray, a mod's panel). `grow` and today's content
    // forms keep the springs' morph exactly; expand, iris, stamp and outline draw the live shape from one progress
    // (SurfaceForm, forms/<Form>.qml); a sheet form (W59.4) runs the card-level FormHost below on the same progress.
    readonly property string formSurface: islandKinds.indexOf(contentKind) >= 0 ? "island" : "panel"
    // What the form opens to: the card at rest, once the panel has shown its first frame and its size is known (I192).
    // Where no morph draws it (a side bar, a look whose cards stand apart) a shape form draws the card through a
    // ShapeLayer instead, in the card's own frame: from the edge it comes from (`slideEdge`), its origin a third of that
    // edge at its middle.
    readonly property bool formWant: open && shown && !gate && (morphMode ? sizeKnown : true)
    readonly property string slideEdge: menuBeside ? besideEdge : (bars.atBottom ? "bottom" : "top")
    readonly property bool slideAcross: slideEdge === "left" || slideEdge === "right"
    readonly property real formFrameW: slideAcross ? card.height : card.width
    readonly property real formFrameH: slideAcross ? card.width : card.height
    SurfaceForm {
        id: run
        surface: stage.formSurface
        want: stage.formWant
        // (a growth mid-way keeps its form through a reversal; from either rest a new form is taken)
        hold: !springs.settled && Math.abs(springs.h - stage.closedFoot) > 1 && Math.abs(springs.h - stage.cardFoot) > 1
        fromCx: stage.morphMode ? stage.originCx - stage.boxL : stage.formFrameW / 2
        fromW: stage.morphMode ? stage.closedW : stage.formFrameW * 0.3
        fromTop: stage.morphMode ? stage.originTop : 0
        fromFoot: stage.morphMode ? stage.closedFoot : 0
        fromR: stage.originR
        pressX: stage.pressAt.x
        pressY: stage.pressAt.y
        toCx: stage.morphMode ? stage.cardCx : stage.formFrameW / 2
        toW: stage.morphMode ? card.width : stage.formFrameW
        toTop: stage.morphMode ? stage.cardTop : 0
        toFoot: stage.morphMode ? stage.cardFoot : stage.formFrameH
        toR: Theme.rLg
        edgeY: stage.morphMode ? stage.barEdgeY : 0
        // Folded back in its form: the pill goes back to the bar first and the shape a moment later (as checkFolded).
        onLanded: at => { if (at <= 0 && !stage.open && stage.shown) { stage.taken = false; handBack.start() } }
    }
    // A retarget while a form moves the card finishes the form and hands the shape to the springs, which morph on.
    onPendingKindChanged: if (pendingKind !== "" && run.busy) run.finish()
    // The shape is drawn from the form while it moves (`sf`), from the springs otherwise.
    readonly property bool useForm: run.mode === "shape" && run.busy && run.shape !== null
    readonly property QtObject sf: useForm ? run.shape : null
    readonly property real lift: sf ? sf.lift : 0
    // The content's cut to the shape (a stamp scales the card with its shape instead) and its opacity in a shape form.
    readonly property bool cutsContent: !sf || sf.clipsContent
    // K83 (W59.4 handover, row 656; W59.9a seamless landing): while a sheet form warps the card, the shape stands at its
    // REST geometry both ways (its fill solid: the sheet composites it) and keeps the island's pill, so the frame at p = 1 is
    // the rest frame with nothing swapped at the landing. The sheet captures only the body's box below the hinge
    // (`sheetBody`: square where it meets the bar), SheetRest draws the rest of it — the bar's side of the hinge exactly as at
    // rest, beside the body × `sheetFillets` — the join's fillets grow back from 0 over the landing (MorphShape `stretch`),
    // the elevation × `sheetShadow`, no compositor blur.
    readonly property bool sheetOn: morphMode && cardHost.sheetSolid
    readonly property bool morphDraws: morphMode
    // The hinge's line (local): the bar's edge on a strip, the body's top under a block (joined: the neck stays the bar's).
    readonly property real hingeY: joined ? cardTop : barEdgeY
    // The body's box below the hinge in the window (whole px: the capture's clip and SheetRest's hole are one edge).
    readonly property rect sheetBody: {
        var x0 = Math.round(cardOutX - boxL), x1 = Math.round(cardOutX - boxL + card.width)
        var y0 = Math.round(hingeY), y1 = Math.ceil(cardFoot)
        return flip ? Qt.rect(x0, morphH - y1, x1 - x0, y1 - y0) : Qt.rect(x0, y0, x1 - x0, y1 - y0)
    }
    // The origin's top (local), for the outline's first rects: the pill's, else the widget's box, else the bar's.
    readonly property real originTop: {
        if (headMode || origin.kind === "pill") return pillTop
        var r = originRect
        if (r !== null && screen) return flip ? screen.height - r.y - r.h : r.y
        return barInset + 4
    }
    // Set on the first presented frame of the shape; the bar's pill is hidden while it is (one island on screen).
    property bool taken: false
    Binding {
        target: IslandGeom
        property: "takenOn"
        value: stage.outName
        when: stage.taken && stage.morphMode && stage.headMode && !stage.handedToView
    }
    // A view with its own chrome (the phone) takes over from the shape once it is in: the shape dissolves into it and the
    // bar gets its pill back while the view stands; closing brings the shape back to fold into the pill.
    readonly property bool handedToView: ownChrome && contentP >= 0.99
    // The open card turns into the island's (the quick card gave way to a face's view): its head takes the pill now; the
    // other way round the pill goes back to the bar.
    onHeadModeChanged: taken = headMode && shown && open && !gate
    // Folded back: the pill is handed back to the bar first, and the shape goes a moment later, so neither surface ever
    // shows no island. A headless shape just goes once it is back in the bar.
    Connections {
        target: springs
        function onHChanged() { stage.checkFolded() }
        function onWChanged() { stage.checkFolded() }
    }
    function checkFolded() {
        if (open || !shown || !morphMode || handBack.running || Math.abs(springs.hTo - closedFoot) > 0.5) return
        // (a form folding the card ends it itself: `run.landed`)
        if (run.formed && (run.busy || run.p > 0)) return
        if (Math.abs(springs.h - springs.hTo) <= 1.5 && Math.abs(springs.w - springs.wTo) <= 3) {
            taken = false
            handBack.start()
        }
    }
    Timer {
        id: handBack
        interval: stage.headMode ? 80 : 0
        onTriggered: {
            if (stage.open) return
            stage.shown = false
        }
    }
    // Test only: the morph's state twice a second while the shape is out (KURASHI_STAGE_DEBUG=1).
    Timer {
        interval: 500
        repeat: true
        running: stage.debugLog && stage.shown && stage.morphMode
        onTriggered: console.log("stage-morph cx=" + springs.cx.toFixed(1) + " w=" + springs.w.toFixed(1) + " h=" + springs.h.toFixed(1)
            + " to=" + springs.cxTo.toFixed(1) + "," + springs.wTo.toFixed(1) + "," + springs.hTo.toFixed(1)
            + " running=" + !springs.settled + " content=" + stage.contentP.toFixed(2) + " open=" + stage.open + " gate=" + stage.gate
            + " kind=" + stage.contentKind + " origin=" + stage.origin.kind + " card=" + card.width + "x" + card.height
            + " win=" + stage.width + "x" + stage.height + "+" + stage.boxL)
    }
    // Test only (the debug log's): where the shape starts on the output — its edge and inset, the head (the pill's rect) and
    // the foot it hangs from — in output px, so a test compares it with the bar's own log (test-bars.sh, row 512).
    function firstLog() {
        var sh = screen ? screen.height : 0
        function y(v) { return Math.round(flip ? sh - v : v) }
        var x0 = Math.round(originCx - closedW / 2), x1 = Math.round(originCx + closedW / 2)
        var head = headMode ? [x0, y(flip ? pillTop + pillH : pillTop), x1, y(flip ? pillTop : pillTop + pillH)].join(",") : "-"
        return "edge=" + morphEdge + " inset=" + Math.round(barInset) + " head=" + head + " foot=" + y(closedFoot)
            + " dx=" + (pillGeom ? Math.round(pillGeom.dx) : "-")
    }
    function lerp(a, b, t) { return a + (b - a) * t }
    function clamp01(v) { return Math.max(0, Math.min(1, v)) }
    // How far the shape has grown out of its origin, 0..1 (the foot against the card's): corners, tint and ring follow it.
    // (a shape form: its own `grow`, and `tint` for fill, corners and ring)
    // (a sheet form: the card at rest, both ways — W59.9a)
    readonly property real tgrow: sheetOn ? 1 : sf ? sf.grow : clamp01((springs.h - closedFoot) / Math.max(1, cardFoot - closedFoot))
    readonly property real ttint: sheetOn ? 1 : sf ? sf.tint : tgrow
    // The drawn shape, in window px: squash & stretch narrows it while its foot moves fast (I113); a shape form's scale
    // is about the bar's edge (the hinge).
    readonly property real shapeW: sheetOn ? card.width : sf ? Math.max(0, sf.w * sf.sx) : Math.max(0, springs.wOut * (1 - springs.squeeze))
    readonly property real shapeCx: sheetOn ? cardCx : sf ? sf.cx : springs.cxOut - boxL
    readonly property real shapeFoot: sheetOn ? cardFoot : sf ? barEdgeY + (sf.foot - barEdgeY) * sf.sy : springs.hOut
    readonly property real cardCx: cardOutX + card.width / 2 - boxL
    // K61: how far the shape's body is from its place at rest, in output axes: its centre and its foot against the
    // card's (0 once grown), so the panel's sheet comes out with the body as it grows.
    readonly property point shapeCarry: Qt.point(shapeCx - cardCx, (flip ? -1 : 1) * (shapeFoot - cardFoot))
    // The pill's corners (square corners: radius.full 0) and its centre at rest.
    readonly property real pillR: Math.min(Theme.rFull, pillH / 2)
    readonly property real pillCx: pillOutCx - boxL
    // The line the body hangs from: the pill's foot (the joined head), the strip's edge, or the widget's block's foot.
    readonly property real hangE: headMode ? pillTop + pillH : origin.e
    // The body: the whole shape on a strip with a head; in the joined topologies what grows out from under the head or
    // the block, from its foot to the card's rect; headless on a strip, from the strip's edge. The view is cut to it.
    readonly property real bodyTop0: joined ? lerp(hangE, cardTop, tgrow)
        : (headMode ? pillTop : barEdgeY)
    readonly property real bodyTop: sf && bodyTop0 > barEdgeY ? barEdgeY + (bodyTop0 - barEdgeY) * sf.sy : bodyTop0
    readonly property real bodyH: Math.max(0, shapeFoot - bodyTop)
    // The shape's fill: the pill's at first (a head), the card's once grown, at the panel's opacity (I114); a boxed pill
    // has the strip under it. A headless shape is the card's from the start.
    readonly property color shapeFill: {
        // (I277: a card is the sheet it grows out of — the bar's surface colour, not the container's)
        var c = headMode ? Qt.tint(boxed ? Theme.surface : Theme.containerHigh, Qt.alpha(Theme.surface, ttint)) : Theme.surface
        // (solid while a sheet form warps it: the sheet composites a translucent fill at its fallback, W59.4)
        return Qt.alpha(c, sheetOn ? 1 : Theme.panel.a)
    }
    // I160: the head over the bar's strip, translucent over translucent, made one layer as the card grows: lighter by the
    // strip's own opacity (0 when the two are equal; the strip's colour shows there, as the rest of the bar's).
    readonly property real stripA: Theme.surfaceAlpha.a
    readonly property real headA: stripA >= 0.999 ? Theme.panel.a : Math.max(0, (Theme.panel.a - stripA) / (1 - stripA))
    // I337: on a strip (no block of its own to join: line, flat, bevel) the open card hangs from the bar's edge by its
    // fillets — the head, the part inside the bar, melts into the strip as it grows (the face rides on the strip), so no
    // box with corners of its own stands in the bar. Joined, the head is the island's block and keeps the panel's fill.
    readonly property color headFill: Qt.alpha(shapeFill, lerp(Theme.panel.a, joined ? headA : 0, ttint))
    // The neck of a headless joined shape: under the block the origin stands in (its bar group, or the pill), as near the
    // body's centre as the block's flat foot allows — so it slides along the block with the body — and letting go once
    // the body has travelled past the block (the card then floats under the bar; it is caught again on the way back).
    readonly property var homeBlock: {
        var rev = IslandGeom.revision
        if (!joined || !shown || headMode) return null
        var R = Math.min(Theme.rFull, (Theme.barH - 8) / 2)
        if (origin.kind === "pill") return { x: pillOutCx - pillW / 2, w: pillW, r: pillR }
        var keys = ["group:right", "group:workspaces", "group:tasks"]
        for (var i = 0; i < keys.length; i++) {
            var g = IslandGeom.rectOf(outName, keys[i])
            if (g && originCx >= g.x && originCx <= g.x + g.w) return { x: g.x, w: g.w, r: R }
        }
        return { x: origin.x, w: origin.w, r: 0 }
    }
    readonly property real neckInset: Theme.rLg / 2 + 10
    readonly property real neckLo: homeBlock ? homeBlock.x + homeBlock.r + neckInset - boxL : originCx - boxL
    readonly property real neckHi: homeBlock ? Math.max(neckLo, homeBlock.x + homeBlock.w - homeBlock.r - neckInset - boxL) : neckLo
    readonly property real neckWant: Math.max(neckLo, Math.min(neckHi, shapeCx))
    readonly property real neckRoom: Math.max(0, shapeW / 2 - Theme.rLg / 2 - Math.min(Theme.rLg, shapeW / 2) - 12)
    readonly property real neckCx: Math.max(shapeCx - neckRoom, Math.min(shapeCx + neckRoom, neckWant))
    readonly property real neckAttach: headMode ? 1 : clamp01(1 - Math.abs(neckCx - neckWant) / 32)
    // The view comes in once the shape has nearly grown (fade + 0.98 -> 1, <= 160 ms) and leaves first (90 ms).
    // Once in, the view stays while the card only grows or shrinks a little (a slot filling): `reached` latches until the
    // panel closes or swaps.
    readonly property bool near: Math.abs(springs.hTo - cardFoot) < 1 && Math.abs(springs.wTo - card.width) < 1 && springs.pw > 0.92 && springs.ph > 0.6 && (springs.pcx > 0.97 || Math.abs(springs.cx - springs.cxTo) < 16)
    property bool reached: false
    onNearChanged: if (near && open && shown && !gate && !swapping && viewReady) reached = true
    onViewReadyChanged: if (viewReady && near && open && shown && !gate && !swapping) reached = true
    onReachedChanged: recordSize()
    onSwappingChanged: reached = false
    onGateChanged: reached = false
    // S21 (the user): a sheet form folds the card closed WITH its content on the pages, as it unfolded it — the content
    // stays until the form has landed (the capture is live: a content cut at the close's start folded empty paper).
    readonly property bool sheetCloses: run.sheet && run.dir === "close" && run.busy && viewReady
    readonly property bool contentWanted: (open && shown && !gate && !swapping && viewReady && (reached || near)) || sheetCloses
    property real contentP: 0
    onContentWantedChanged: {
        contentP = contentWanted ? 1 : 0
        if (debugLog) console.log("stage-morph content=" + contentWanted + " pw=" + springs.pw.toFixed(2) + " ph=" + springs.ph.toFixed(2)
            + " pcx=" + springs.pcx.toFixed(2) + " h=" + springs.h.toFixed(1) + "/" + springs.hTo.toFixed(1) + " sh=" + springs.sh.toFixed(1)
            + " swapping=" + swapping + " t=" + Date.now())
    }
    // (a shape form shows the content itself: no fade after it)
    Behavior on contentP {
        enabled: stage.shown && Theme.quickMs > 0 && !run.formed
        NumberAnimation { duration: stage.contentWanted ? 160 : 90; easing.type: Easing.OutCubic }
    }
    onShownChanged: if (!shown) run.reset()
    // A view with its own chrome: the shape dissolves into it (all of it but the bar's rule copy, I161).
    readonly property real shapeFade: ownChrome ? 1 - contentP : 1

    // ---- K83 (W59.3): the card-level form host — the WHOLE card as drawn (the shape: fill, material, outline, ring,
    // shadows, the head and its face; the card: its view, and its own fill and frame where it does not morph) in one item,
    // so a sheet form (W59.4: fold, roll, book, crumple …) captures all of it while it moves. Its progress is the form's
    // while a sheet form is latched, else 1 (identity: today's content forms stay with the inner Entrance, the morph with
    // the springs). `origin`: the pill's or the widget's box in this window; `edge`: the hinge (the bar's side). Inside,
    // `formLayer` draws through the shape forms' mask while one moves (iris, stamp, outline: FormMask, a layer only then).
    FormHost {
        id: cardHost
        surface: stage.formSurface
        anchors.fill: parent
        edge: stage.flip ? "bottom" : "top"
        origin: Qt.rect(stage.originCx - stage.closedW / 2 - stage.boxL,
            stage.flip ? stage.morphH - stage.closedFoot : stage.originTop,
            stage.closedW, Math.max(1, stage.closedFoot - stage.originTop))
        direction: run.dir
        progress: run.sheet ? run.p : 1
        pressAt: isNaN(stage.pressAt.x) ? stage.pressAt : Qt.point(stage.pressAt.x, stage.flip ? stage.morphH - stage.pressAt.y : stage.pressAt.y)
        // (W59.9a: on a morph the sheet captures the body's box only — `bodySrc`; SheetRest draws the rest)
        source: stage.morphMode && run.sheet ? bodySrc : card
        // (a sheet form at 0: nothing yet; its layer exists only while 0 < p < 1)
        visible: !run.sheet || run.p > 0
    Item {
        id: formLayer
        anchors.fill: parent
        layer.enabled: run.masked && stage.morphMode
        // (kept whole: the bar's strip up to its edge, less the 1-px band a strip's card lays over the bar's edge in its
        // own fill — it comes with the card; a ruled strip's band is the rule itself, which the bar leaves to the shape)
        layer.effect: FormMask {
            form: run.shape
            keep: stage.barEdgeY - (Theme.outlineW > 0 || stage.joined ? 0 : 1)
            flipped: stage.flip
        }
    // W59.9a: the whole drawing (the shape, its material and face, the card): while a sheet form warps the card on a morph,
    // SheetRest takes it into one layer at its rest geometry, and the sheet captures the body's box of it (`bodySrc`).
    Item {
        id: fullDraw
        width: formLayer.width
        height: formLayer.height

    Item {
        id: shapeBox
        visible: stage.shown && stage.morphMode && stage.shapeFade > 0.001
        width: stage.morphW
        height: stage.morphH
        transform: Scale { yScale: stage.flip ? -1 : 1; origin.y: stage.morphH / 2 }
        // The soft chrome's shadow under the head and the body (static RectangularShadows that follow the springs; I122:
        // every morphing panel casts it).
        SoftShadow {
            visible: stage.joined && stage.headMode
            opacity: stage.shapeFade * cardHost.sheetShadow
            x: stage.pillCx - stage.pillW / 2
            y: stage.pillTop
            width: stage.pillW
            height: stage.pillH
            radius: stage.pillR
            direction: stage.flip ? -1 : 1
        }
        SoftShadow {
            visible: shape.h > 1
            opacity: stage.shapeFade * cardHost.sheetShadow
            x: shape.x0
            y: shape.y0
            width: shape.w
            height: shape.h
            radius: Math.min(shape.rTop, shape.rBot)
            direction: stage.flip ? -1 : 1
        }
        // W57 (K78): the card's elevation; cut along the bar it grows out of (one sheet with it).
        Elevation {
            id: cardElev
            // I337: a card grown out of a strip casts from the bar's edge down (the bar is the same sheet), never onto it.
            readonly property real topY: stage.joined || !stage.morphMode ? shape.y0 : Math.max(shape.y0, stage.barEdgeY)
            visible: shape.h > 1 && shape.y0 + shape.h - topY > 1
            opacity: stage.shapeFade * (1 - stage.lift) * cardHost.sheetShadow
            x: shape.x0
            y: topY
            width: shape.w
            height: shape.y0 + shape.h - topY
            radius: Math.min(shape.rTop, shape.rBot)
            level: 3
            cutTop: stage.joined || stage.morphMode
            cutLeft: stage.mergesL
            cutRight: stage.mergesR
            mirrorY: stage.flip ? -1 : 1
        }
        // K83 (stamp): the card still above the screen casts one level higher, the shadow tightening as it lands.
        Elevation {
            visible: cardElev.visible && stage.lift > 0.001
            opacity: stage.shapeFade * stage.lift * cardHost.sheetShadow
            x: cardElev.x
            y: cardElev.y
            width: cardElev.width
            height: cardElev.height
            radius: cardElev.radius
            level: 4
            cutTop: cardElev.cutTop
            mirrorY: cardElev.mirrorY
        }
        MorphShape {
            id: shape
            visible: shapeBox.visible
            anchors.fill: parent
            joined: stage.joined
            headless: !stage.headMode
            hx0: stage.pillCx - stage.pillW / 2
            hy0: stage.pillTop
            hw: stage.pillW
            hh: stage.pillH
            hr: stage.pillR
            neckF: Theme.rJoin
            neckCx: stage.neckCx
            attach: stage.neckAttach
            neckScale: stage.sf ? 1 : springs.neckScale
            x0: stage.shapeCx - stage.shapeW / 2
            y0: stage.bodyTop
            w: stage.shapeW
            h: stage.bodyH
            rTop: stage.joined || !stage.headMode ? Theme.rLg : stage.lerp(stage.pillR, Theme.rLg, stage.ttint)
            rBot: stage.headMode ? stage.lerp(stage.pillR, Theme.rLg, stage.ttint) : Math.min(Theme.rLg, stage.lerp(stage.originR, Theme.rLg, stage.ttint))
            // (liquid's thread; under a sheet form the join's fillets grow back from 0 over the landing, W59.9a)
            stretch: stage.sheetOn ? cardHost.sheetFillets : stage.sf ? stage.sf.neck : 1
            edgeY: stage.joined ? stage.hangE : stage.barEdgeY
            neck: stage.neckR
            edgeL: stage.mergesL ? stage.holeL - stage.boxL : -1e6
            edgeR: stage.mergesR ? stage.holeR - stage.boxL : 1e6
            fill: stage.shapeFill
            headFill: stage.headMode ? stage.headFill : stage.shapeFill
            fade: stage.shapeFade
            ringScale: 0.5 + 0.5 * stage.ttint
            flip: stage.flip
            barCx: stage.outW / 2 - stage.boxL
        }
        // The shape's fill as a mask for its relief (I168): the fill path alone, in white, drawn only into `shapeMask`'s
        // texture, which is redrawn when the path changes (while the shape morphs) and never at rest.
        Shape {
            id: maskShape
            visible: reliefBox.masked
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillColor: "white"
                PathSvg { path: reliefBox.masked ? shape.fillPath : "" }
            }
        }
        // Parked outside the window, as TileSheet's copies: a texture provider needs its paint node.
        StillCopy {
            id: shapeMask
            x: -100000
            width: parent.width
            height: parent.height
            sourceItem: reliefBox.masked ? maskShape : null
            hideSource: true
        }
        Connections {
            target: reliefBox.masked ? shape : null
            function onFillPathChanged() { shapeMask.scheduleUpdate() }
        }
    }
    // K59, K61 (I168): the panel's material — one relief over the shape's whole box, clipped to the shape's own fill path
    // (head, neck fillets and body; the outline and ring stay flat), under the views; with `texture.text` over them. The
    // head stays registered with the bar it sits in (no carry above its foot; on a strip, whose own relief shows through
    // the translucent fill, weighed by the fill's opacity so it is shaded about once); the body carries its sheet as it
    // grows (`shapeCarry`: the body's foot and centre against the card's at rest, 0 once grown). The sheet registers by
    // window pixel, so the Stage's mirror for a bottom bar does not move it.
    // I460 prototype: the wash over the panel's shape (head, fillets, body), under the views.
    Item {
        visible: Theme.washOn && shape.visible && shape.w > 2 && shape.h > 2
        opacity: stage.shapeFade
        width: stage.morphW
        height: stage.morphH
        transform: Scale { yScale: stage.flip ? -1 : 1; origin.y: stage.morphH / 2 }
        Loader {
            anchors.fill: parent
            active: parent.visible
            sourceComponent: Wash {
                anchors.fill: parent
                mask: shapeMask
                fill: Qt.alpha(stage.shapeFill, 1)
                strength: stage.shapeFill.a
            }
        }
    }
    Item {
        id: reliefBox
        readonly property bool on: Theme.texShell && shape.visible && shape.w > 2 && shape.h > 2
        // The shape's mask serves the relief or the wash (I460).
        readonly property bool masked: (Theme.texShell || Theme.washOn) && shape.visible && shape.w > 2 && shape.h > 2
        z: Theme.texText ? 2 : 0
        visible: on
        opacity: stage.shapeFade
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
                bandEdge: stage.joined ? shape.edgeY : stage.barEdgeY
                bandWeight: stage.joined ? 1 : Theme.panel.a
            }
        }
    }
    // The island's face, in the shape's head where the pill was (it moves to the card's centre as the shape widens).
    CompactFace {
        id: headFace
        active: stage.shown && stage.morphMode && stage.headMode
        // Not visible while idle: its geometry follows the pill (hover), and a visible item that moves costs a frame (Ma).
        visible: active
        face: stage.pillGeom ? (stage.pillGeom.face || "clock") : "clock"
        animate: stage.shown
        opacity: stage.shapeFade
        // Joined: the face stays in the head, the island's block; on a strip it rides the shape's centre.
        x: Math.round((stage.joined ? stage.pillCx : stage.shapeCx) - width / 2)
        y: stage.flip ? stage.morphH - stage.pillTop - stage.pillH : stage.pillTop
        width: Math.max(stage.pillW, wantW + 2 * Theme.pad)
        height: stage.pillH
    }

    // ---- card under the Island: the island's view or the quick card, session menu, or tray menu
    // (K83: where no morph draws a shape form, the ShapeLayer draws the card in it; a plain item otherwise)
    ShapeLayer {
        anchors.fill: parent
        run: stage.morphMode ? null : run
        edge: stage.slideEdge
    // K102: a card apart casts as a card does.
    Elevation {
        visible: stage.placed && stage.shown
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        radius: card.radius
        level: 3
        opacity: stage.p
    }
    RoundBox {
        id: card
        visible: stage.shown
        // Media, the calendar and the quick settings card (docs/ux/quick-settings.md) need the wider card; a mod panel
        // asks for its card width (contract row 66); the session menu is as wide as its row of tiles; the rest keep 360 px.
        // I192: while the view is being made, the size it had last time (see `cachedSize`).
        readonly property bool fromCache: !stage.viewReady && stage.cachedSize !== null
        // W53.0b: a card made full screen by its title bar takes the room its output has (the title bar's own size).
        // (W53.5: a view may ask for more with `cardWant` — the calendar's grid in a wide pixel face.)
        width: stage.full ? stage.fullW : fromCache ? stage.cachedSize.w : ["media", "clock", "quick", "power", "bluetooth"].indexOf(stage.contentKind) >= 0
            ? Math.max(400, Math.min(stage.viewWant, stage.fullW))
            : (stage.contentKind === "mod" ? stage.modCardWidth
            : (stage.contentKind === "session" ? Math.max(360, menu.implicitWidth + 2 * (Theme.pad + 4)) : 360))
        height: stage.full ? stage.fullH : fromCache ? stage.cachedSize.h : (stage.viewing ? col.implicitHeight
            : stage.contentKind === "session" ? menu.implicitHeight : trayCol.implicitHeight) + 2 * stage.cardPad + stage.titleH + 2 * stage.frameW
        onWidthChanged: stage.recordSize()
        onHeightChanged: stage.recordSize()
        // I458: what a hover opened stays while the pointer is on it, and is the user's once they press in it.
        HoverHandler { onHoveredChanged: hovered ? Peeks.hoverHold() : Peeks.hoverLeave() }
        PointHandler { acceptedButtons: Qt.AllButtons; onActiveChanged: if (active) Peeks.hoverKeep() }
        // K28: a slot filling or emptying grows or shrinks the card smoothly. Off until the view is in (the reveal is
        // the shape's growth, or the slide), so opening the card does not animate its height from the closed size, nor
        // from the size it had last time to the view's when it arrives (I192: the springs take that up).
        // Clipped, so a grown row is revealed by the card's edge rather than drawn over its margin.
        clip: true
        Behavior on height {
            enabled: stage.resizing || (stage.open && !stage.gate && stage.viewReady && (stage.morphMode ? stage.reached : stage.p >= 1))
            NumberAnimation {
                duration: stage.resizing ? (stage.full ? Theme.openMs : Theme.closeMs) : Theme.stdMs
                easing.type: Easing.BezierSpline
                easing.bezierCurve: stage.resizing ? (stage.full ? Theme.openCurve : Theme.closeCurve) : Theme.enterCurve
            }
        }
        Behavior on width {
            enabled: stage.resizing
            NumberAnimation {
                duration: stage.full ? Theme.openMs : Theme.closeMs
                easing.type: Easing.BezierSpline
                easing.bezierCurve: stage.full ? Theme.openCurve : Theme.closeCurve
            }
        }
        // Slide, not fade: group opacity over a text-heavy card cost ~4 MiB of retained heap (K16).
        // The island's card (W21): the shape draws it; this holds the view where the grown shape will be, fading in after it.
        x: stage.morphMode ? stage.cardOutX - stage.boxL : stage.placedRoom
        y: stage.morphMode ? (stage.flip ? stage.morphH - stage.cardTop - height : stage.cardTop)
            : stage.placedRoom + (inner.form === "grow" ? -stage.slide * (1 - stage.p) : 0)   // above the surface edge = clipped away
        // (K83: a shape form shows the content as its form says — revealed, through the iris, landing with the stamp, or
        // not until the outline has stepped out; the 0.98 → 1 settle is the grow's)
        opacity: stage.morphMode ? (stage.sf ? stage.sf.content : stage.contentP) : 1
        scale: stage.morphMode && !stage.sf ? 0.98 + 0.02 * stage.contentP : 1
        transformOrigin: stage.flip ? Item.Bottom : Item.Top
        // W53.5: a stepped look's card grows out of its middle in held steps (FF6's boxes open from the centre strip).
        // K83 (stamp): the card scales with its shape about the bar's edge.
        transform: [
            Scale {
                origin.y: card.height / 2
                yScale: stage.stepped && !stage.morphMode && !run.formed ? Math.max(0.001, stage.p) : 1
            },
            Scale {
                origin.x: stage.shapeCx - card.x
                origin.y: (stage.flip ? stage.morphH - stage.barEdgeY : stage.barEdgeY) - card.y
                xScale: stage.sf ? stage.sf.sx : 1
                yScale: stage.sf ? stage.sf.sy : 1
            }
        ]
        radius: Theme.rLg
        color: stage.morphDraws || stage.ownChrome ? "transparent" : Qt.alpha(Theme.surface, cardHost.sheetSolid ? 1 : Theme.panel.a)
        // K62: with a pen in effect the pen draws the card's outline (1 px further in: the card clips its children).
        border.width: stage.morphDraws || stage.ownChrome || cardPen.active || stage.frameW > 0 ? 0 : (Theme.outlineW > 0 ? Theme.outlineW : 1)
        border.color: Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline
        Loader {
            id: cardPen
            z: 5
            anchors.fill: parent
            active: Theme.penOutline && !stage.morphDraws && !stage.ownChrome && card.visible && stage.frameW === 0
            sourceComponent: PenOutline {
                radius: card.radius
                inset: 1
                color: card.border.color
                lineWidth: Theme.outlineW > 0 ? Theme.outlineW : 1
                seed: 0x57A6E
            }
        }
        // W53.5: the look's banded fill and frame round the card (an RPG window, the PS2's glow line), under the views;
        // not while the shape draws the card, nor round a view with its own chrome.
        Loader {
            anchors.fill: parent
            active: !stage.morphDraws && !stage.ownChrome && (Theme.frame !== "" || Theme.fillBands > 1)
            sourceComponent: PanelDress { radius: card.radius; alpha: Theme.panel.a }
        }
        // I460 prototype: the wash on the card's fill.
        Loader {
            anchors.fill: parent
            anchors.margins: Theme.outlineW
            active: Theme.washOn && !stage.morphDraws && !stage.ownChrome
            sourceComponent: Wash {
                anchors.fill: parent
                radius: Math.max(0, card.radius - Theme.outlineW)
                fill: Qt.alpha(Theme.panel, 1)
                strength: Theme.panel.a
            }
        }
        // K59: the card is a material area (its fill is the panel's); the relief lies under the views. Off while the
        // island morphs, where the shape draws the card.
        Loader {
            anchors.fill: parent
            anchors.margins: Theme.outlineW
            active: Theme.texShell && !Theme.texText && !stage.morphDraws && !stage.ownChrome
            sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, card.radius - Theme.outlineW) }
        }
        // With `texture.text` the relief lies over the views too: their text and icons sink into the same sheet.
        Loader {
            z: 1
            anchors.fill: parent
            anchors.margins: Theme.outlineW
            active: Theme.texShell && Theme.texText && !stage.morphDraws && !stage.ownChrome
            sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, card.radius - Theme.outlineW) }
        }
        // W53.4: the look's ground pattern (Aqua's pinstripes) on the window's ground, under the views; made only while the
        // look has one.
        Loader {
            anchors.fill: parent
            anchors.margins: Theme.outlineW
            active: !stage.morphDraws && !stage.ownChrome && Theme.decor("pattern.kind", "none") !== "none"
                && Theme.decor("pattern.strength", 0) > 0
            sourceComponent: Pattern { radius: card.radius }
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
            readonly property bool cuts: stage.morphMode && stage.cutsContent
            readonly property real cutTop: cuts ? Math.max(0, Math.min(card.height, shapeTop - card.y)) : 0
            readonly property real cutBottom: cuts
                ? Math.max(cutTop, Math.min(card.height, shapeTop + stage.bodyH - card.y)) : card.height
            readonly property real cutLeft: cuts
                ? Math.max(0, Math.min(card.width, stage.shapeCx - stage.shapeW / 2 - card.x)) : 0
            readonly property real cutRight: cuts
                ? Math.max(cutLeft, Math.min(card.width, stage.shapeCx + stage.shapeW / 2 - card.x)) : card.width
            x: cutLeft
            y: cutTop
            width: cutRight - cutLeft
            height: cutBottom - cutTop
            clip: cuts
        // The look's form (W53, row 591; decor/Entrance): sliding in, the card's content arrives as the look moves on the
        // card's progress; `grow` (the default) leaves it to the card's slide, and the morph is the shape's own motion.
        Entrance {
            id: inner
            surface: stage.formSurface
            x: -reveal.cutLeft
            y: -reveal.cutTop
            width: card.width
            height: card.height
            progress: stage.morphMode || stage.stepped || run.formed ? 1 : stage.p
            edge: stage.flip ? "bottom" : "top"

        // W53.0b (K80): the card's title bar, where the style draws one (`runtime.ui.title`, the daemon's: the buttons
        // and what each does). The style's own strip (`decor.title`, components/decor/title/<Name>.qml) when it loads,
        // else a plain one from tokens. Every button runs `ui.title {button}`; Esc still closes.
        Item {
            id: titleStrip
            visible: stage.titled
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: stage.frameW }
            height: stage.titleH
            // TitleHost turns the daemon's buttons into the part's contract (TitleBase) and says each press (rows 560/591).
            // The caption greys while the card does not hold the keyboard (row 595: the window is not the active one).
            TitleHost {
                id: styleTitle
                anchors.fill: parent
                active: has && stage.titled
                spec: stage.titleDoc
                title: stage.cardTitle
                focused: card.activeFocus
                onPressed: (id) => Store.act("ui.title", { button: id })
            }
            Loader {
                anchors.fill: parent
                active: stage.titled && !styleTitle.ready
                sourceComponent: plainTitle
            }
        }

        Column {
            id: col
            visible: stage.viewing
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: stage.cardPad + stage.frameW }
            anchors.topMargin: stage.cardPad + stage.titleH + stage.frameW
            spacing: Theme.pad
            // Its height is the view's implicit one (an explicit binding to it loops in Qt).
            Loader {
                id: view
                width: col.width
                active: stage.shown && stage.viewing
                asynchronous: true
                // Test only: one line per view made (an open must make one view, I192).
                onLoaded: if (stage.debugLog) console.log("stage-view made " + stage.contentKind + " t=" + Date.now())
                sourceComponent: stage.viewing ? stage.views[stage.contentKind] : null
            }
            // No Close button (I279): Esc or a click elsewhere (ClickAway) closes the island and quick cards.
        }

        SessionMenu {
            id: menu
            visible: stage.contentKind === "session"
            active: stage.open && stage.contentKind === "session"
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.pad + 4 + stage.frameW }
            anchors.topMargin: Theme.pad + 4 + stage.titleH + stage.frameW
        }

        Column {
            id: trayCol
            visible: stage.contentKind === "tray"
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.pad + 4 + stage.frameW }
            anchors.topMargin: Theme.pad + 4 + stage.titleH + stage.frameW
            spacing: Theme.gap
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                width: trayCol.width
                elide: Text.ElideRight
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                font.family: Theme.fam(text, Theme.families)
                text: stage.moduleKey !== "" ? moduleMenu.title : (stage.trayItem(stage.trayKey).title || I18n.tr("frontend.tray.menu"))
            }
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
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
                tree: stage.moduleKey !== "" ? moduleMenu.tree : stage.trayTree
                errText: stage.trayErr
                onChosen: item => {
                    if (stage.moduleKey !== "") {
                        if (moduleMenu.choose(item)) Store.act("ui.close")
                        return
                    }
                    Store.act("tray.menu_event", {id: stage.trayKey, item: item})
                    Store.act("ui.close")
                }
            }
        }
        // Row 595: under a captioned look the card is a window — its frame (`decor.border.width` px, 98's 3) drawn as the
        // window edge: the light line outside (EDGE_RAISED on windows, measured on 98), the dark pair at the bottom right,
        // the face's own px inside; in place of the 1 px outline.
        Loader {
            z: 6
            anchors.fill: parent
            active: stage.frameW > 0
            // W53.2: a look without the bevel chrome draws its own window frame (XP's blue, 7's glass) round the card.
            sourceComponent: Theme.bevelW > 0 ? bevelFrame : edgeFrame
            Component {
                id: bevelFrame
                BevelEdge {
                    light: Theme.bevelLight2
                    light2: Theme.bevelLight
                    w: Theme.crisp(1, Screen.devicePixelRatio)
                }
            }
            Component { id: edgeFrame; WindowEdge { radius: card.radius } }
        }
        }
        }
    }
    }
    }
    // W59.9a: the rest of the joined card while a sheet form warps its body (see `sheetOn`), and the body's box of it, which
    // the sheet form captures (the FormHost's source: hinged on the box's top, square where it meets the bar).
    SheetRest {
        id: sheetRest
        anchors.fill: parent
        on: stage.sheetOn
        draw: fullDraw
        body: stage.sheetBody
        hingeY: stage.flip ? stage.morphH - stage.hingeY : stage.hingeY
        barAbove: !stage.flip
        k: cardHost.sheetFillets
    }
    Item {
        id: bodySrc
        x: stage.sheetBody.x
        y: stage.sheetBody.y
        width: stage.sheetBody.width
        height: stage.sheetBody.height
        clip: true
        SheetRest.Body { rest: sheetRest }
    }
    }
    }
    // K83 (outline): the stepped outline rects while the outline form moves the card (outside the masked layer).
    OutlineRects {
        width: stage.morphW
        height: stage.morphH
        rects: stage.sf && stage.sf.outline ? stage.sf.rects : []
        transform: Scale { yScale: stage.flip ? -1 : 1; origin.y: stage.morphH / 2 }
    }
}
