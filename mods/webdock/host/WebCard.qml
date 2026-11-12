import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "core"
import "core/motion"
import "core/motion/curves.js" as C
import "components"
import "components/motion"
import "frames"

// The web dock's card (docs/ux/webdock.md "Layout per edge", "Sites", "Motion", "Keyboard and a11y"; MODS.md "Web dock",
// "Host"; K40): one layer-shell surface at the dock's edge, mapped only while the shown pin is a web pin in extended
// mode, so hidden it draws nothing. The surface is the card plus `grace` px on every side but the strip's: the pointer's
// enter and leave of that margin are the card's `webdock.hover` reports, and the window's keyboard focus gained or lost
// its `webdock.engage`. The header holds the page's navigation and the dock's controls; the body holds one WebPage per
// pin in `keep`. The card sends `webdock.*` actions and draws what `mod.webdock` says; it never decides a mode or a pin.
// W21 (K42): the phone size is a phone seen from the front (PhoneFrame, the shell's own file through a link): the status
// row (the time, the page's host), the title in a pill under it, the page, and the header's controls as a bottom bar over
// the home indicator. The large size stays a plain card with the header on top.
// W69 (I468; docs/ux/webdock.md "Page styles"): the card wears one of three frames (`style`, mod.webdock `page_style`):
// the phone, which morphs into a tablet lying sideways in the large size (DeviceFrame, `wide`); one half of an opened
// spiral notebook (NotebookBack, NotebookSheet, NotebookWire), whose sheet turns over the binding as it opens and closes
// (PageTurn, the motion engine's `book` sheet); and plain, the page alone on the dock's card. The pages live in one well
// (`pane`) whatever the frame: a style or a size change moves and resizes the well, never re-makes a page.
PanelWindow {
    id: card

    // Set by shell.qml from `mod.webdock` and the host's objects.
    property var pins: []
    property string iconDir: ""
    property var keepWeb: []           // ids of the web pins the host keeps loaded, most recent first
    property string shownId: ""
    property bool open: false          // mode extended and the shown pin a web pin
    property string edge: "right"
    property string size: "phone"      // phone | large
    property string style: "phone"     // page_style (W69): phone | notebook | plain
    // The frames' boxes in the look's corners (frames/FrameBox): the shell's RoundBox, through the host's link.
    readonly property Component roundBox: Component { RoundBox {} }
    property int strip: 56             // geometry.strip: the dock's strip, the card's margin from the edge
    property int phoneWidth: 412       // geometry.width
    property int largePct: 90          // geometry.large
    property int grace: 24             // geometry.grace: the hover margin on the sides away from the strip
    property string newTabs: "dock"    // new_tabs: dock (a link loads in the pin's view) | browser (the default browser)
    property bool engaged: false       // `engaged`: the dock holds the keyboard, so the page takes the first keystroke
    // I98: a keybind reveal (`engaged`, with the open) asks for the keyboard exclusively until the window has the focus,
    // then relaxes to on-demand; the rule and its reasons are in DockWindow.
    property bool winActive: false
    property bool pulseSpent: false
    readonly property bool asksKeys: open && engaged && !winActive && !pulseSpent
    onAsksKeysChanged: if (asksKeys) pulseTimer.restart(); else pulseTimer.stop()
    Timer { id: pulseTimer; interval: 1000; onTriggered: card.pulseSpent = true }
    property string output: ""
    property var profiles: null        // Profiles (the view of each profile, the storage of each pin)
    property var report: null          // function(action, args): the reports and actions the card sends
    // W30: the sidebar rests open on the web pin `sidePin`; its page is drawn in `sideSlot` (SideWindow), not here.
    property string sidePin: ""
    property bool sideOpen: false
    property Item sideSlot: null
    // W72: the bar card rests open on the web pin `cardPin`; its page is drawn in `cardSlot` (SideWindow, `card`).
    property string cardPin: ""
    property bool cardOpen: false
    property Item cardSlot: null
    // W73 ("last opened wins", docs/ux/webdock.md "Which place shows the page"): one page per pin, in the place the daemon
    // names — a place whose pin is shown elsewhere says where (`elsewhere`: edge, sidebar, card). A daemon that does not
    // say (the mock) leaves W72's order: the sidebar, then the bar card, then this edge card.
    property string sideElsewhere: ""
    property string cardElsewhere: ""
    property string edgeElsewhere: ""
    readonly property bool sideLive: sideOpen && sideElsewhere === ""
    readonly property bool shownInSide: sideLive && shownId === sidePin
    readonly property var sidePage: sideLive ? pageFor(sidePin, rep.count) : null
    readonly property bool cardLive: cardOpen && cardElsewhere === "" && !(sideLive && sidePin === cardPin)
    readonly property bool shownInCard: cardLive && shownId === cardPin
    readonly property var cardPage: cardLive ? pageFor(cardPin, rep.count) : null
    // W73: a pin's page stays Active while hidden and silent when the daemon says so (its grace after a sound, a pin that
    // keeps running in the background), or while it plays.
    function awakeOf(id) {
        var p = pinById(id)
        return !!p && (p.awake === true || p.audible === true || p.background === true)
    }

    readonly property int gap: Theme.gap
    readonly property bool sideways: edge === "left" || edge === "right"
    readonly property bool isLarge: size === "large"
    readonly property var screenObj: screenFor(output)
    readonly property real screenW: screenObj ? screenObj.width : 1920
    readonly property real screenH: screenObj ? screenObj.height : 1080
    // The window's size as the compositor configured it. The window is stretched across the usable area of the output
    // along the edge (exclusiveZone 0 keeps clear of a top bar and reserves nothing): its height, for a card on a side.
    // Quickshell does not carry a stretched configure into `height` (probe: 100, then 0); the item's attached Window does.
    property int availW: 0
    property int availH: 0
    Connections {
        target: area.Window
        function onWidthChanged() { card.availW = Math.round(area.Window.width) }
        function onHeightChanged() { card.availH = Math.round(area.Window.height) }
    }
    // The height the card is sized by: the usable height the window is stretched to. A top or bottom edge's window spans
    // the usable area across the edge too (anchored to all four sides, below), so a bar on that axis is kept clear (I100).
    readonly property real basisH: availH
    // Phone: `width` wide, as tall as twice that or the usable height allows, less a gap at each end (the lead's rule);
    // large: `large` % of the output's width, the usable height less a gap at each end.
    // W69: the styles (rule 4: the style is the setting's value, never a look's name).
    readonly property bool isNotebook: style === "notebook"
    readonly property bool isPlain: style === "plain"
    readonly property bool isPhone: !isNotebook && !isPlain
    // W69: the size change is a morph in every style (`wide` 0 the phone size … 1 the large one) on the profile's curves
    // (a Glide; at once with motion off). The phone becomes a tablet lying sideways on the way (DeviceFrame).
    readonly property Glide wideGlide: Glide { to: card.isLarge ? 1 : 0; enabled: card.moves }
    readonly property real wide: holdWide >= 0 ? holdWide : Math.max(0, Math.min(1, wideGlide.value))
    // The size at rest at its end: the window has the card's size then; while it moves the window holds the larger end
    // (a layer surface is not resized every frame) and the page keeps its pixels (`pageBox`).
    readonly property bool wideRest: holdWide < 0 && (isLarge ? wide >= 0.9995 : wide <= 0.0005)
    readonly property int phoneW: phoneWidth
    readonly property int phoneH: Math.max(0, Math.round(Math.min(2 * phoneWidth, basisH - 2 * gap)))
    readonly property int largeW: Math.round((sideways ? screenW : availW) * largePct / 100)
    readonly property int largeH: Math.max(0, Math.round(basisH - 2 * gap))
    readonly property int cardW: wideRest ? (isLarge ? largeW : phoneW) : Math.round(phoneW + (largeW - phoneW) * wide)
    readonly property int cardH: wideRest ? (isLarge ? largeH : phoneH) : Math.round(phoneH + (largeH - phoneH) * wide)
    readonly property int winW: wideRest ? cardW : Math.max(phoneW, largeW)
    readonly property int winH: wideRest ? cardH : Math.max(phoneH, largeH)
    // The phone's own chrome (the title pill, the bottom bar) while the device is a phone; the tablet, the notebook and
    // the plain card have the header on top.
    readonly property bool phoneLook: isPhone && wide < 0.5
    // The phone's controls fade out and in again while the frame turns into the tablet (and back).
    readonly property real chromeK: isPhone && !wideRest ? Math.min(1, Math.abs(wide - 0.5) * 4) : 1
    // Where the card is in the window: a card on the right stands against the strip (the window is card + margin wide at
    // rest, wider while the size moves), one on the left too; a card on a top or bottom edge is centred across.
    readonly property int cardX: sideways ? (edge === "right" ? Math.max(0, availW - cardW) : 0) : Math.max(0, Math.round((availW - cardW) / 2))
    // A bottom card stands against the strip: the window ends at the strip, so the card's top gap is what is left over.
    readonly property int cardY: edge === "top" ? 0 : edge === "bottom" ? Math.max(0, availH - cardH)
        : Math.max(0, Math.round((availH - cardH) / 2))
    // The input: the card plus `grace` on each side but the strip's (a margin over the strip would take its clicks). The
    // window's mask takes input here only; the rest of the usable area is the desktop's.
    readonly property int padL: edge === "left" ? 0 : grace
    readonly property int padR: edge === "right" ? 0 : grace
    readonly property int padT: edge === "top" ? 0 : grace
    readonly property int padB: edge === "bottom" ? 0 : grace
    readonly property int inX: Math.max(0, cardX - padL)
    readonly property int inY: Math.max(0, cardY - padT)
    readonly property int inW: Math.min(availW, cardX + cardW + padR) - inX
    readonly property int inH: Math.min(availH, cardY + cardH + padB) - inY

    // The card's place in the usable area, for the test (KURASHI_WEBDOCK_DEBUG=1): x y width height, then the area.
    function geometryLog() {
        if (debugLog) console.log("webdock-debug card", cardX, cardY, cardW, cardH, availW, availH)
    }
    onCardXChanged: geometryLog()
    onCardYChanged: geometryLog()
    onCardWChanged: geometryLog()
    onCardHChanged: geometryLog()
    onAvailHChanged: geometryLog()

    // The page the card shows: none while the sidebar shows the same pin (the sidebar wins; the card says so).
    readonly property var activePage: shownInSide || shownInCard ? null : pageFor(shownId, rep.count)
    readonly property var shownPin: pinById(shownId)
    readonly property string shownTarget: targetOf(shownId)
    readonly property string shownView: modeOf(shownId)
    // The home button shows once the page has left the pin's address (docs/ux/webdock.md "Layout per edge").
    readonly property bool homeShown: !!activePage && shownTarget !== "" && !activePage.atTarget
    // The theme's motion profile: `none` and `reduced` (reduced motion, the accessibility axis; K83 D1, as the shell's
    // DockWindow reads it) fade instead of sliding, turning or morphing.
    readonly property string motionProfile: Theme.tokens["motion.profile"] || "calm"
    readonly property bool moves: motionProfile !== "none" && motionProfile !== "reduced"
    readonly property bool springs: moves && Theme.springOn
    // Under none the card fades over this fixed time (docs/ux/webdock.md "Motion": fade only); motion.quick_ms is 0
    // there, and a zero-length fade is a cut (I99). The fade is the slide's `slide` value read as opacity below.
    readonly property int fadeMs: 120
    readonly property int slideMs: moves ? (Theme.stdMs > 0 ? 180 : 0) : fadeMs
    // The distance the body slides out by, toward its edge; none when the motion is reduced.
    readonly property int away: !moves ? 0 : edge === "right" ? cardW : edge === "left" ? -cardW
        : edge === "bottom" ? cardH : -cardH

    // W69: the notebook opens in two acts on one progress (`nbP`): the cover and the coil slide in from the edge
    // (0 → 0.35), then the sheet turns over the binding and lands flat (0.25 → 1, PageTurn); closing runs it back. On
    // the profile's open and close curves, stretched by the `book` form's pace (a sheet form tells a longer story, S21).
    // Reduced motion and motion off: the fade, as every style.
    readonly property bool turns: isNotebook && moves
    readonly property real bookPace: { var m = Theme.formMeta("book"); return m && m.pace > 0 ? m.pace : 1 }
    readonly property var bookCurves: {
        var c = Theme.motionCurves, f = bookPace
        if (!c || f === 1) return c
        return { open: C.stretch(c.open, f), close: C.stretch(c.close, f), fast: C.stretch(c.fast, f),
                 effects: C.stretch(c.effects, f) }
    }
    property Driver nbDrv: Driver {
        curves: card.bookCurves
        keepVelocity: true
        onLanded: at => { if (at <= 0 && !card.open && card.turns) card.mapped = false }
    }
    readonly property real nbP: holdOpen >= 0 ? holdOpen : nbDrv.value
    function smooth(s) { s = Math.max(0, Math.min(1, s)); return s * s * (3 - 2 * s) }
    function sub(x, a, b) { return Math.max(0, Math.min(1, (x - a) / (b - a))) }
    readonly property real coverIn: smooth(sub(nbP, 0, 0.35))
    readonly property real turnP: sub(nbP, 0.25, 1)
    // The style changes while the card is up: the notebook stands where the card is (a cut, brief "Motion").
    onTurnsChanged: nbDrv.snap(open ? 1 : 0)
    // The body's offset toward its edge: the slide (phone, plain, the fade's 0) or the notebook's cover.
    readonly property real slideNow: holdOpen >= 0 && !turns ? 1 - holdOpen : slide
    readonly property real offsetK: turns ? 1 - coverIn : slideNow

    // Test only (KURASHI_WEBDOCK_HOLD=<file>, mods/webdock/test/test-styles.sh): the file holds "open <p>" or "wide <p>",
    // and the card stands at that point of its opening or of its size change (shots by progress, not by timing); an
    // empty file lets go. The file is watched (inotify), nothing polls; none of it exists without the variable.
    readonly property string holdPath: Quickshell.env("KURASHI_WEBDOCK_HOLD") || ""
    property real holdOpen: -1
    property real holdWide: -1
    function applyHold(text) {
        var m = /^\s*(open|wide)\s+([0-9.]+)/.exec(String(text || ""))
        holdOpen = m && m[1] === "open" ? Math.max(0, Math.min(1, Number(m[2]))) : -1
        holdWide = m && m[1] === "wide" ? Math.max(0, Math.min(1, Number(m[2]))) : -1
        if (holdOpen >= 0) mapped = true
        // Plain in a panel form: the form's own progress is held (and let go to where the card wants to be).
        if (isPlain && pRun.formed) {
            if (holdOpen >= 0) pRun.drv.track(holdOpen, 0, 1)
            else pRun.drv.snap(pRun.want ? 1 : 0)
        }
        if (debugLog) console.log("webdock-debug hold", holdOpen, holdWide)
    }
    Loader {
        active: card.holdPath !== ""
        sourceComponent: Item {
            FileView {
                path: card.holdPath
                watchChanges: true
                onFileChanged: reload()
                onLoaded: card.applyHold(text())
                onLoadFailed: card.applyHold("")
            }
        }
    }

    property bool menuOpen: false      // the overflow menu of the header
    property bool hoverInside: false   // the last `inside` reported for the card's margin
    readonly property bool debugLog: Quickshell.env("KURASHI_WEBDOCK_DEBUG") === "1"   // test-only (test-host.sh)

    function screenFor(name) {
        var all = Quickshell.screens
        for (var i = 0; i < all.length; i++)
            if (all[i].name === name) return all[i]
        return all.length > 0 ? all[0] : null
    }
    function pinById(id) {
        for (var i = 0; i < pins.length; i++)
            if (pins[i].id === id) return pins[i]
        return null
    }
    function pageFor(id, n) {
        for (var i = 0; i < rep.count; i++) {
            var page = rep.itemAt(i)
            if (page && page.pinId === id) return page
        }
        return null
    }
    function targetOf(id) {
        var p = pinById(id)
        return p && p.target ? p.target : ""
    }
    function modeOf(id) {
        var p = pinById(id)
        return p && profiles ? profiles.viewOf(p.profile || p.id) : "desktop"
    }
    function currentUrl() {
        return activePage ? String(activePage.engine.url) : ""
    }
    function openBrowser() {
        if (activePage && report) report("webdock.open_external", { url: currentUrl() })
    }
    // Home: the pin's address again (a new history entry, so Back returns to the page the reader left).
    function goHome() {
        if (activePage && shownTarget !== "") activePage.engine.url = shownTarget
    }
    function toggleView() {
        if (shownPin && report) report("webdock.view", { pin: shownId, view: shownView === "mobile" ? "desktop" : "mobile" })
    }
    function focusPage() {
        if (activePage) activePage.engine.forceActiveFocus()
    }
    // Ctrl+L: the keyboard path into the header (I78). Back takes it, or Reload when Back is off; Tab walks on.
    function focusHeader() {
        if (!activePage) return
        var first = back.enabled ? back : reloadButton
        first.forceActiveFocus()
    }
    function focusMenu() {
        openItem.forceActiveFocus()
    }
    // The window's keyboard focus (K40): a report when it is gained and when it is lost. A loss without a gain before it
    // (the window's first activation state, as Qt reports it on a new surface) is no change of the focus, so none is sent:
    // the daemon would read it as a leave and hide the dock.
    property bool engageSent: false
    function reportEngage(on) {
        if (on === engageSent) return
        engageSent = on
        if (report) report("webdock.engage", { on: on })
    }
    // The card's margin, the whole surface: its enter and leave are one report each (the daemon's hysteresis, K40).
    function reportHover(inside) {
        if (inside === hoverInside) return
        hoverInside = inside
        if (report) report("webdock.hover", { part: "card", inside: inside, output: screenObj ? screenObj.name : output })
    }
    // Tooltips (docs/ux/webdock.md "Keyboard and a11y"): the name of the control under the pointer or the keyboard,
    // after a short rest. One at a time, and only while a control is held (a timer exists only while armed, Ma).
    property var tipItem: null
    property string tipText: ""
    property real tipX: 0
    function tipFor(item, on) {
        if (on && item && item.tip !== "") {
            tipItem = item
            tipTimer.restart()
        } else if (!on && tipItem === item) {
            tipTimer.stop()
            tipItem = null
            tipText = ""
        }
    }
    function syncViews() {
        for (var i = viewModel.count - 1; i >= 0; i--)
            if (keepWeb.indexOf(viewModel.get(i).pid) < 0) viewModel.remove(i)
        for (var j = 0; j < keepWeb.length; j++) {
            var have = false
            for (var k = 0; k < viewModel.count; k++)
                if (viewModel.get(k).pid === keepWeb[j]) have = true
            // The profile is made here, not in a binding: making one changes the profiles' own state. A pin waits
            // for its profile (the storage root comes with the document, which may arrive after the keep list).
            var prof = have || !profiles ? null : profiles.forPin(pinById(keepWeb[j]))
            if (!have && prof) viewModel.append({ pid: keepWeb[j], prof: prof })
        }
    }

    onKeepWebChanged: syncViews()
    Connections {
        target: card.profiles
        function onStorageRootChanged() { card.syncViews() }
    }
    onOpenChanged: {
        if (open) { mapped = true; pulseSpent = false }
        else {
            reportHover(false)
            menuOpen = false
        }
        if (isPlain && moves) pRun.want = open
        if (turns) {
            slide = 0
            var t = open ? 1 : 0
            if (nbDrv.to !== t) nbDrv.to = t
            else if (nbDrv.value !== t && !nbDrv.running) nbDrv.go()
        } else if (isPlain && pRun.formed) {
            // The panel form draws the opening and the closing (a shape or a sheet form): no slide meanwhile.
            nbDrv.snap(open ? 1 : 0)
            slideAnim.stop()
            slide = 0
        } else {
            nbDrv.snap(open ? 1 : 0)
            slideAnim.to = open ? 0 : 1
            slideAnim.restart()
        }
        if (open) Qt.callLater(card.focusPage)
    }
    // The dock asks for the keyboard (`engaged`) while the card is the front part: the page takes the first keystroke.
    onEngagedChanged: if (engaged && open) Qt.callLater(card.focusPage)
    onShownIdChanged: menuOpen = false
    onMenuOpenChanged: if (menuOpen && more.activeFocus) Qt.callLater(card.focusMenu)

    screen: screenObj
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: asksKeys ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "kurashi-webdock"
    // The window spans the usable area of the output: anchored to all four sides, so the compositor stretches it between
    // the bars, along a side edge's length and, on a top or bottom edge, across the usable width and height (I100).
    // exclusiveZone 0 keeps it clear of a bar without reserving anything (the default reserved the implicit size, 300 px,
    // on the edge in the probe). The margin of `strip` on the dock's own side keeps the card off the strip.
    exclusiveZone: 0
    color: "transparent"
    anchors.top: true
    anchors.bottom: true
    anchors.left: edge === "left" || !sideways
    anchors.right: edge === "right" || !sideways
    margins.top: edge === "top" ? strip : 0
    margins.bottom: edge === "bottom" ? strip : 0
    margins.left: edge === "left" ? strip : 0
    margins.right: edge === "right" ? strip : 0
    implicitWidth: sideways ? winW + grace : 0
    implicitHeight: sideways ? 0 : winH + grace
    // The input: the card and its margin only (the rest of the window is the desktop's, and it is transparent).
    mask: Region {
        x: card.inX
        y: card.inY
        width: card.mapped ? card.inW : 0
        height: card.mapped ? card.inH : 0
    }

    // Mapped (a layer surface) only while it shows: an unmapped card draws nothing (0 frames, Ma). The slide runs on
    // Theme.stdMs (180 ms) under the calm and lively profiles; under none the fade's fixed `fadeMs` (120 ms).
    property real slide: 1
    property bool mapped: false
    visible: mapped
    Component.onCompleted: {
        syncViews()
        geometryLog()
        wideGlide.snap(isLarge ? 1 : 0)
        if (open) {
            mapped = true
            slide = 0
            nbDrv.snap(1)
            nbDrv.to = 1
        }
    }
    // Test only: the style and the size's progress, and which side of the card the notebook's coil is on.
    onStyleChanged: if (debugLog) console.log("webdock-debug style", style)
    onMappedChanged: if (debugLog) console.log("webdock-debug mapped", mapped, style, isPlain ? pRun.form + ":" + pRun.mode : "")
    onWideRestChanged: {
        if (!wideRest) {
            // The page keeps its pixels while the size moves: the larger of now and the end (see `pageBox`).
            pageHoldW = Math.max(pane.width, pane.width + (isLarge ? largeW : phoneW) - cardW)
            pageHoldH = Math.max(pane.height, pane.height + (isLarge ? largeH : phoneH) - cardH)
        }
        if (debugLog && wideRest) console.log("webdock-debug wide", isLarge ? 1 : 0, isLarge ? largeW : phoneW,
            isLarge ? largeH : phoneH)
    }
    property real pageHoldW: 0
    property real pageHoldH: 0
    // (test only: the side of the card the coil's axis is drawn on, from the notebook's own geometry)
    readonly property string coilSide: {
        if (!isNotebook) return ""
        var p = nb.pt(nb.along / 2, nb.axisD)
        return sideways ? (p.x < cardW / 2 ? "left" : "right") : (p.y < cardH / 2 ? "top" : "bottom")
    }
    onCoilSideChanged: if (debugLog && coilSide !== "") console.log("webdock-debug coil", edge, coilSide)

    // W69 plain (CONTRACT-CHANGE row 694, I391): the card opens and closes in the motion profile's panel form, as the
    // shell's own dock card does (mods/webdock/qml/DockWindow.qml): a shape form (expand, iris, stamp, outline) drawn
    // through ShapeLayer's mask, a sheet form through FormHost's capture of the card, anything else on today's slide.
    // The form's frame: x along the edge, y away from it; the window's edge on the strip's side is y = 0 (the strip's
    // own surface lies beyond it). No origin here (the strip's tile is in the shell's window): the 32 px mouth in the
    // middle of the card's span, as the row asks. A style change while open is a cut (standOpen / reset).
    readonly property SurfaceForm pRun: SurfaceForm {
        surface: "panel"
        shapes: ["expand", "iris", "stamp", "outline"]
        fromCx: card.alongMid
        fromW: 32
        fromTop: 0
        fromFoot: 0
        fromR: Theme.rSm
        toCx: card.alongMid
        toW: card.sideways ? card.cardH : card.cardW
        toTop: 0
        toFoot: card.sideways ? card.cardW : card.cardH
        toR: Theme.rLg
        edgeY: 0
        onLanded: at => { if (at <= 0 && !card.open && card.isPlain) card.mapped = false }
    }
    readonly property real alongMid: sideways ? cardY + cardH / 2 : cardX + cardW / 2
    readonly property bool formDraws: isPlain && pRun.formed && (pRun.busy || pRun.want)
    onIsPlainChanged: {
        if (isPlain && open && moves) pRun.standOpen()
        else if (!isPlain) { pRun.quiet = true; pRun.want = false; pRun.quiet = false; pRun.reset() }
    }
    NumberAnimation {
        id: slideAnim
        target: card
        property: "slide"
        // The rise is a spring (K42: the theme's overshoot, into the margin on the strip's side); the way out has none.
        duration: card.slideMs + (card.open && card.springs ? 60 : 0)
        easing.type: card.open && card.springs ? Easing.OutBack : Easing.OutCubic
        easing.overshoot: Theme.overshoot
        // (the page turn and the panel form unmap the card where they land, not here)
        onStopped: if (!card.open && !card.turns && !(card.isPlain && card.pRun.formed)) card.mapped = false
    }
    // The status row's time: svc.clock (in the host's scope since row 118), watched only while the phone is mapped (Ma).
    Watch { doc: "svc.clock"; active: card.mapped && card.isPhone }
    readonly property var clockDoc: Store.docs["svc.clock"] || ({})
    // The page's host name for the status row ("" for a file or an address without one).
    function hostOf(u) {
        var m = /^[a-z][a-z0-9+.-]*:\/\/([^\/?#:]+)/i.exec(String(u || ""))
        return m ? m[1] : ""
    }
    Timer {
        id: tipTimer
        interval: 400
        onTriggered: {
            if (!card.tipItem) return
            card.tipX = card.tipItem.mapToItem(frame, card.tipItem.width / 2, 0).x
            card.tipText = card.tipItem.tip
        }
    }

    // The whole surface, the margin included: its pointer enter and leave are the card's hover reports. The window's
    // keyboard focus (the attached Window.active: Quickshell's window type has no `active`) is the engage report (K40).
    // On top of the card: the page takes the hover of the card below it, and a passive handler at the bottom never sees it.
    Item {
        id: area
        anchors.fill: parent
        z: 100
        HoverHandler {
            onHoveredChanged: card.reportHover(hovered)
        }
        Window.onActiveChanged: {
            card.winActive = Window.active
            if (Window.active) card.pulseSpent = true
            card.reportEngage(Window.active)
            if (Window.active && card.engaged && card.open) card.focusPage()
        }
    }
    // Ctrl+L enters the header; the page is not told (it may take Ctrl+L for itself, but the card is the chrome's key).
    Shortcut {
        sequence: "Ctrl+L"
        enabled: card.open
        onActivated: card.focusHeader()
    }

    // The pages, one per web pin in `keep`: created when a pin is first kept, destroyed when it leaves `keep`.
    ListModel { id: viewModel }

    // W69 plain: the panel form's host (a sheet form captures the card) and its shape layer (a shape form masks it). At
    // rest, and in the other styles, both are plain items: progress 1, no layer.
    FormHost {
        id: fHost
        anchors.fill: parent
        surface: "panel"
        edge: card.edge
        direction: card.pRun.dir
        progress: card.pRun.sheet && card.formDraws ? card.pRun.p : 1
        visible: !(card.pRun.sheet && card.formDraws) || card.pRun.p > 0
        source: body
        ShapeLayer {
            anchors.fill: parent
            run: card.isPlain ? card.pRun : null
            edge: card.edge
            Item {
                id: body
                // Drawn once the window has its configured size (the first frame after a map has none, and no card then).
                visible: card.mapped && card.availW > 0 && card.availH > 0
                x: card.cardX + (card.sideways ? card.offsetK * card.away : 0)
                y: card.cardY + (card.sideways ? 0 : card.offsetK * card.away)
                width: card.cardW
                height: card.cardH
                opacity: card.moves ? 1 : 1 - card.slideNow

                // ---- the frame under the page: the device, the notebook's cover and lower sheets, or the plain card ----
                DeviceFrame {
                    id: phone
                    visible: card.isPhone
                    anchors.fill: parent
                    theme: Theme
                    wide: card.wide
                    box: card.roundBox
                    screenColor: Theme.container
                    statusLeft: Text {
                        height: phone.statusH
                        verticalAlignment: Text.AlignVCenter
                        text: (card.clockDoc.hh ?? "--") + ":" + (card.clockDoc.mm ?? "--")
                        color: Theme.fg
                        font.pixelSize: Theme.fsLabel
                        font.weight: Theme.wBold
                        font.family: Theme.fam(text, Theme.families)
                    }
                    statusRight: Text {
                        height: phone.statusH
                        width: Math.min(implicitWidth, phone.screen.width / 2 - 70)
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideLeft
                        text: card.activePage ? card.hostOf(card.activePage.engine.url) : ""
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.weight: Theme.wBold
                        font.family: Theme.fam(text, Theme.families)
                    }
                }
                NotebookGeom {
                    id: nb
                    width: body.width
                    height: body.height
                    edge: card.edge
                }
                Loader {
                    anchors.fill: parent
                    active: card.isNotebook
                    sourceComponent: NotebookBack {
                        theme: Theme
                        geom: nb
                        box: card.roundBox
                    }
                }

                // The leaf: what the notebook's page turn captures and turns — the sheet with the header and the page on it. In
                // the other styles it is the whole card, standing still.
                Item {
                    id: leaf
                    readonly property rect r: card.isNotebook ? nb.sheet : Qt.rect(0, 0, body.width, body.height)
                    x: r.x
                    y: r.y
                    width: r.width
                    height: r.height
                    Loader {
                        anchors.fill: parent
                        active: card.isNotebook
                        sourceComponent: NotebookSheet {
                            theme: Theme
                            geom: nb
                            headY: frame.y + header.y + header.height
                        }
                    }

                    Rectangle {
                        id: frame
                        // Phone: the phone's screen (the status row and the home indicator are its own); notebook: the sheet inside
                        // its margins (more on the bound side, clear of the punched slots); plain: the whole card.
                        readonly property real bindM: 20
                        readonly property real freeM: 10
                        x: card.isPhone ? phone.screen.x : card.isNotebook ? (card.edge === "left" ? bindM : freeM) : 0
                        y: card.isPhone ? phone.screen.y : card.isNotebook ? (card.edge === "top" ? bindM : 8) : 0
                        width: card.isPhone ? phone.screen.width
                            : card.isNotebook ? parent.width - bindM * (card.sideways ? 1 : 0) - freeM * (card.sideways ? 1 : 2) : parent.width
                        height: card.isPhone ? phone.screen.height
                            : card.isNotebook ? parent.height - (card.sideways ? 8 + 14 : bindM + (card.edge === "top" ? 14 : 8)) : parent.height
                        radius: card.isPhone ? phone.screenRadius : card.isPlain ? Theme.rLg : 0
                        color: card.isPlain ? Theme.container : "transparent"
                        clip: true
                        // The page's corners follow the card's radius (I78) where they meet it — the plain card's, the tablet's screen —
                        // through a layer masked by that rounded shape. The phone's page sits between the title and the bottom bar,
                        // clear of the screen's corners, and the notebook's page is a square sheet pasted in: no layer.
                        readonly property bool masked: card.isPlain || (card.isPhone && !card.phoneLook)
                        layer.enabled: masked
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: frameMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1
                        }
                        // The mask is hidden, but its texture is the mask: it needs its own layer (a hidden item without one is
                        // empty, and the whole card went blank in the first run).
                        Rectangle {
                            id: frameMask
                            visible: false
                            anchors.fill: parent
                            radius: frame.radius
                            color: "white"
                            layer.enabled: frame.masked
                        }

                        // Phone: the title in a pill under the status row (the page's title, or the pin's name), its load progress
                        // along the pill's foot. Not a control: the press that gives the card the keyboard may land on it.
                        Item {
                            id: titleBar
                            visible: card.phoneLook
                            opacity: card.chromeK
                            y: phone.statusH
                            width: parent.width
                            height: card.phoneLook ? 40 : 0
                            Rectangle {
                                visible: Theme.sinkX !== 0 || Theme.sinkY !== 0
                                x: pill.x + Theme.sinkX
                                y: pill.y + Theme.sinkY
                                width: pill.width
                                height: pill.height
                                radius: height / 2
                                color: Theme.line
                            }
                            Rectangle {
                                id: pill
                                x: 10
                                y: 2
                                width: parent.width - 20
                                height: 32
                                radius: height / 2
                                color: Theme.containerHigh
                                border.width: Theme.outlineW
                                border.color: Theme.outlineColor
                                clip: true
                                Text {
                                    id: phoneTitle
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    text: header.title
                                    color: Theme.fg
                                    font.pixelSize: Theme.fsLabel
                                    font.weight: Theme.wBold
                                    font.family: Theme.fam(text, Theme.families)
                                    onWidthChanged: if (card.phoneLook && card.report && card.debugLog)
                                        console.log("webdock-debug title width", Math.round(width))
                                }
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: Theme.outlineW
                                    x: pill.height / 2
                                    height: 2
                                    radius: 1
                                    width: card.activePage ? (pill.width - pill.height) * card.activePage.engine.loadProgress / 100 : 0
                                    visible: !!card.activePage && card.activePage.engine.loading
                                    color: Theme.accent
                                }
                            }
                        }

                        Item {
                            id: header
                            // A y, not switching anchors: a top anchor and a bottom anchor swapped in one change stretched the bar
                            // (both held for a moment) after a large-to-phone switch.
                            // The tablet's row stands under its status row (W69).
                            y: card.phoneLook ? parent.height - phone.homeH - height : (card.isPhone ? phone.statusH : 0)
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: card.phoneLook ? 40 : 36
                            opacity: card.chromeK
                            // Phone: the controls spread evenly across the bottom bar (the title is in its pill on top).
                            readonly property int count: 7 + (card.homeShown ? 1 : 0)
                            readonly property real spread: card.phoneLook
                                ? Math.max(0, (width - 2 * 12 - count * 32) / (count - 1)) : 0

                            readonly property var page: card.activePage
                            readonly property string title: (page && page.engine.title) ? page.engine.title
                                : (card.shownPin ? card.shownPin.title : "")

                            // Escape steps back on the chrome (MODS.md "Shell side"): extended to compact, compact to hidden.
                            Keys.onEscapePressed: (event) => {
                                if (card.report) card.report("webdock.back", {})
                                event.accepted = true
                            }

                            // Navigation: back and forward follow the engine's history.
                            Row {
                                id: nav
                                anchors.left: parent.left
                                anchors.leftMargin: card.phoneLook ? 12 : 4
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: header.spread
                                HostButton {
                                    keyed: card.phoneLook
                                    id: back
                                    glyph: "‹"
                                    icon: "arrow_back_ios_new"
                                    a11y: I18n.tr("webdock.nav.back")
                                    enabled: !!(header.page && header.page.engine.canGoBack)
                                    tipFn: card.tipFor
                                    onClicked: header.page.engine.goBack()
                                }
                                HostButton {
                                    keyed: card.phoneLook
                                    id: forward
                                    glyph: "›"
                                    icon: "arrow_forward_ios"
                                    a11y: I18n.tr("webdock.nav.forward")
                                    enabled: !!(header.page && header.page.engine.canGoForward)
                                    tipFn: card.tipFor
                                    onClicked: header.page.engine.goForward()
                                }
                            }
                            // The title comes first: it keeps what the controls leave (at 360 px, 120 px at least; I78).
                            Text {
                                id: titleText
                                visible: !card.phoneLook
                                anchors.left: nav.right
                                anchors.leftMargin: 6
                                anchors.right: tools.left
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: header.title
                                color: Theme.fg
                                font.pixelSize: Theme.fsLabel
                                font.family: Theme.fam(text, Theme.families)
                                onWidthChanged: if (!card.phoneLook && card.report && card.debugLog)
                                    console.log("webdock-debug title width", Math.round(width))
                            }
                            Row {
                                id: tools
                                anchors.right: parent.right
                                anchors.rightMargin: card.phoneLook ? 12 : 4
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: header.spread
                                HostButton {
                                    keyed: card.phoneLook
                                    id: home
                                    visible: card.homeShown
                                    glyph: "⌂"
                                    icon: "home"
                                    a11y: I18n.tr("webdock.nav.home")
                                    tipFn: card.tipFor
                                    onClicked: card.goHome()
                                }
                                HostButton {
                                    keyed: card.phoneLook
                                    id: reloadButton
                                    glyph: "↻"
                                    icon: "refresh"
                                    a11y: I18n.tr("webdock.nav.reload")
                                    enabled: !!header.page
                                    tipFn: card.tipFor
                                    onClicked: header.page.engine.reload()
                                }
                                // The view and the size show the state they are in; a press switches it (the tooltip names it).
                                HostButton {
                                    keyed: card.phoneLook
                                    id: viewToggle
                                    shape: card.shownView === "mobile" ? "phone" : "desktop"
                                    a11y: I18n.tr(card.shownView === "mobile" ? "webdock.host.view.mobile" : "webdock.host.view.desktop")
                                    enabled: !!card.shownPin
                                    tipFn: card.tipFor
                                    onClicked: card.toggleView()
                                }
                                HostButton {
                                    keyed: card.phoneLook
                                    id: sizeToggle
                                    shape: card.isLarge ? "wide" : "narrow"
                                    a11y: I18n.tr(card.isLarge ? "webdock.host.size.large" : "webdock.host.size.phone")
                                    tipFn: card.tipFor
                                    onClicked: card.report("webdock.size", { size: card.isLarge ? "phone" : "large" })
                                }
                                HostButton {
                                    keyed: card.phoneLook
                                    id: more
                                    glyph: "…"
                                    icon: "more_horiz"
                                    a11y: I18n.tr("webdock.nav.more")
                                    tipFn: card.tipFor
                                    onClicked: card.menuOpen = !card.menuOpen
                                }
                                HostButton {
                                    keyed: card.phoneLook
                                    glyph: "×"
                                    icon: "close"
                                    a11y: I18n.tr("webdock.nav.collapse")
                                    tipFn: card.tipFor
                                    onClicked: card.report("webdock.collapse", {})
                                    // Tab from the header's last control goes back into the page (Ctrl+L brought the focus in).
                                    Keys.onTabPressed: (event) => {
                                        card.focusPage()
                                        event.accepted = true
                                    }
                                }
                            }
                        }

                        // Blocked permissions of the shown pin: one chip each, until the next load (brief "Sites").
                        Row {
                            id: chips
                            anchors.top: card.phoneLook ? titleBar.bottom : header.bottom
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            spacing: 6
                            visible: card.open && !!card.shownPin && !!card.shownPin.blocked && card.shownPin.blocked.length > 0
                            height: visible ? 24 : 0
                            Repeater {
                                model: card.shownPin && card.shownPin.blocked ? card.shownPin.blocked : []
                                delegate: HostChip {
                                    required property string modelData
                                    text: I18n.tr("webdock.blocked." + modelData)
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // The page's load progress, under the header (large; the phone draws it on the title's pill).
                        Rectangle {
                            visible: !card.phoneLook && !!card.activePage && card.activePage.engine.loading
                            anchors.top: header.bottom
                            anchors.left: parent.left
                            height: 2
                            width: card.activePage ? parent.width * card.activePage.engine.loadProgress / 100 : 0
                            color: Theme.accent
                        }

                        Item {
                            id: pane
                            anchors.top: chips.visible ? chips.bottom : (card.phoneLook ? titleBar.bottom : header.bottom)
                            anchors.topMargin: card.phoneLook || card.isNotebook ? 6 : 0
                            anchors.left: parent.left
                            anchors.right: parent.right
                            // (the tablet's page ends over its home indicator)
                            anchors.bottom: card.phoneLook ? header.top : parent.bottom
                            anchors.bottomMargin: card.isPhone && !card.phoneLook ? phone.homeH : 0
                            clip: true

                            // The pages' box: the well's size at rest; while the size moves, the larger of now and the end, so the
                            // site keeps its layout and reflows once (W69: never a reload, never a reflow per frame).
                            Item {
                                id: pageBox
                                width: card.wideRest ? pane.width : Math.max(pane.width, card.pageHoldW)
                                height: card.wideRest ? pane.height : Math.max(pane.height, card.pageHoldH)
                            Repeater {
                                id: rep
                                model: viewModel
                                delegate: WebPage {
                                    required property string pid
                                    required property var prof
                                    pinId: pid
                                    target: card.targetOf(pid)
                                    profile: prof
                                    report: card.report
                                    iconDir: card.iconDir
                                    mode: card.modeOf(pid)
                                    readonly property bool inSide: card.sideLive && pid === card.sidePin && card.sideSlot !== null
                                    // W72: the bar card's page, unless the sidebar shows the same pin
                                    readonly property bool inCard: !inSide && card.cardLive && pid === card.cardPin
                                        && card.cardSlot !== null
                                    home: pageBox
                                    sideHost: inSide ? card.sideSlot : (inCard ? card.cardSlot : null)
                                    debugLog: card.debugLog
                                    active: inSide || inCard || (card.open && pid === card.shownId)
                                    awake: card.awakeOf(pid)
                                    newTabsInDock: card.newTabs !== "browser"
                                }
                            }
                            }
                            // The notebook's page is pasted in: a hairline round it.
                            Rectangle {
                                anchors.fill: parent
                                z: 5
                                visible: card.isNotebook
                                color: "transparent"
                                border.width: 1
                                border.color: Qt.alpha(Theme.outline, 0.7)
                            }

                            // The skeleton holds the card's colour until the first paint: no white flash (brief "Motion").
                            Rectangle {
                                anchors.fill: parent
                                color: Theme.containerHigh
                                visible: card.open && !!card.activePage && !card.activePage.painted
                                z: 2
                                Text {
                                    anchors.centerIn: parent
                                    text: I18n.tr("webdock.loading")
                                    color: Theme.dim
                                    font.pixelSize: Theme.fsLabel
                                    font.family: Theme.fam(text, Theme.families)
                                }
                            }

                            // A load that failed: the code, retry, and the browser (brief "States").
                            Column {
                                anchors.centerIn: parent
                                spacing: Theme.gap
                                visible: card.open && !!card.activePage && !!card.activePage.loadError
                                z: 3
                                Text {
                                    width: pane.width - 2 * Theme.pad
                                    wrapMode: Text.Wrap
                                    horizontalAlignment: Text.AlignHCenter
                                    text: I18n.tr("webdock.error.load") + "\n"
                                        + I18n.tr("webdock.error.code").replace("{code}", card.activePage && card.activePage.loadError ? String(card.activePage.loadError.code) : "")
                                    color: Theme.fg
                                    font.pixelSize: Theme.fs
                                    font.family: Theme.fam(text, Theme.families)
                                }
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: Theme.gap
                                    HostButton {
                                        label: I18n.tr("webdock.error.retry")
                                        primary: true
                                        onClicked: card.activePage.engine.reload()
                                    }
                                    HostButton {
                                        label: I18n.tr("webdock.open_browser")
                                        onClicked: card.openBrowser()
                                    }
                                }
                            }

                            // The renderer stopped: the daemon says so (`error`), and reload brings the page back.
                            Column {
                                anchors.centerIn: parent
                                spacing: Theme.gap
                                visible: card.open && !!card.shownPin && card.shownPin.error === "webdock.error.crashed"
                                z: 3
                                Text {
                                    text: I18n.tr("webdock.error.crashed")
                                    color: Theme.fg
                                    font.pixelSize: Theme.fs
                                    font.family: Theme.fam(text, Theme.families)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                HostButton {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    label: I18n.tr("webdock.nav.reload")
                                    primary: true
                                    onClicked: if (card.activePage) card.activePage.engine.reload()
                                }
                            }

                            // W30: the shown pin's page is in the open sidebar (one page per pin): the card says where it is.
                            // (W72: or in the bar's card. W73: with "Show here", which brings it to this card: `webdock.open`
                            // stamps the edge as the place opened last.)
                            Column {
                                anchors.centerIn: parent
                                width: pane.width - 2 * Theme.pad
                                visible: card.open && (card.shownInSide || card.shownInCard)
                                z: 3
                                spacing: Theme.gap
                                Text {
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    horizontalAlignment: Text.AlignHCenter
                                    text: I18n.tr(card.shownInSide ? "webdock.side.elsewhere" : "webdock.card.elsewhere")
                                    color: Theme.dim
                                    font.pixelSize: Theme.fs
                                    font.family: Theme.fam(text, Theme.families)
                                    // (test only: the edge card's notice, test-card.sh)
                                    onVisibleChanged: if (card.debugLog && visible) console.log("webdock-debug edge notice " + text)
                                }
                                HostButton {
                                    id: hereKey
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    label: I18n.tr("webdock.elsewhere.here")
                                    primary: true
                                    onClicked: if (card.report && card.shownId !== "")
                                        card.report("webdock.open", { pin: card.shownId, output: card.output })
                                    // (test only, W74: the key's middle in the window, and the window's size — test-card.sh
                                    // presses it on screen after a hover reveal)
                                    onVisibleChanged: if (card.debugLog && visible) hereLog.restart()
                                    Timer {
                                        id: hereLog
                                        interval: 300
                                        onTriggered: {
                                            var p = hereKey.mapToItem(null, hereKey.width / 2, hereKey.height / 2)
                                            console.log("webdock-debug edge here " + Math.round(p.x) + " " + Math.round(p.y)
                                                + " " + card.availW + " " + card.availH)
                                        }
                                    }
                                }
                            }

                            // The web engine is still starting: the card frame is up before the host is connected.
                            Text {
                                anchors.centerIn: parent
                                visible: card.open && !Store.live
                                z: 3
                                text: I18n.tr("webdock.host.starting")
                                color: Theme.dim
                                font.pixelSize: Theme.fsLabel
                                font.family: Theme.fam(text, Theme.families)
                            }

                            // A sign-in popup is a sheet over the page: its close button is the way back (brief "Sites").
                            HostButton {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 4
                                z: 4
                                visible: !!card.activePage && !!card.activePage.sheet
                                glyph: "×"
                                a11y: I18n.tr("webdock.sheet.close")
                                onClicked: card.activePage.closeSheet()
                            }
                        }

                        // The overflow menu (brief "Layout per edge"): a press outside it closes it, so the page under it gets no press.
                        MouseArea {
                            anchors.fill: parent
                            z: 7
                            visible: card.menuOpen
                            onPressed: card.menuOpen = false
                        }
                        Rectangle {
                            id: menu
                            z: 8
                            visible: card.menuOpen
                            // Large: under the header; phone: over the bottom bar (a y, as the header's).
                            y: card.phoneLook ? header.y - height - 4 : header.y + header.height + 4
                            anchors.right: parent.right
                            anchors.rightMargin: card.phoneLook ? 10 : 4
                            width: Math.min(frame.width - 8, 240)
                            height: menuCol.implicitHeight + 2 * Theme.xs
                            radius: Theme.rSm
                            color: Theme.containerHigh
                            border.width: 1
                            border.color: Theme.outline
                            // Escape closes the menu and gives the focus back to its button.
                            Keys.onEscapePressed: (event) => {
                                card.menuOpen = false
                                more.forceActiveFocus()
                                event.accepted = true
                            }
                            Column {
                                id: menuCol
                                x: Theme.xs
                                y: Theme.xs
                                width: menu.width - 2 * Theme.xs
                                HostButton {
                                    id: openItem
                                    width: menuCol.width
                                    flat: true
                                    start: true
                                    label: I18n.tr("webdock.open_browser")
                                    onClicked: {
                                        card.menuOpen = false
                                        card.openBrowser()
                                    }
                                }
                                HostButton {
                                    id: replaceItem
                                    width: menuCol.width
                                    flat: true
                                    start: true
                                    visible: card.homeShown
                                    label: I18n.tr("webdock.nav.replace")
                                    onClicked: {
                                        card.menuOpen = false
                                        card.report("webdock.retarget", { pin: card.shownId, url: card.currentUrl() })
                                    }
                                }
                            }
                        }

                        // The tooltip of the control under the pointer or the keyboard: under the header, kept inside the card.
                        Rectangle {
                            id: tipBox
                            z: 9
                            visible: card.tipText !== ""
                            y: card.phoneLook ? header.y - height - Theme.xs : header.y + header.height + Theme.xs
                            width: tipLabel.implicitWidth + 2 * Theme.gap
                            height: tipLabel.implicitHeight + 2 * Theme.xs
                            x: Math.max(Theme.xs, Math.min(card.tipX - width / 2, frame.width - width - Theme.xs))
                            radius: Theme.rSm
                            color: Theme.containerHigh
                            border.width: 1
                            border.color: Theme.outline
                            Text {
                                id: tipLabel
                                anchors.centerIn: parent
                                text: card.tipText
                                color: Theme.fg
                                font.pixelSize: Theme.fsCaption
                                font.family: Theme.fam(text, Theme.families)
                            }
                        }
                    }
                }

                // ---- over the page ----
                // Plain: the card's outline, the look's (the page is masked to the card's radius under it).
                FrameBox {
                    anchors.fill: parent
                    visible: card.isPlain && Theme.outlineW > 0
                    box: card.roundBox
                    radius: Theme.rLg
                    color: "transparent"
                    borderWidth: Theme.outlineW
                    borderColor: Theme.outlineColor
                }
                // The page turn (W69): only while the sheet turns (Ma), the sheet captured and hidden meanwhile.
                Loader {
                    id: turnLoader
                    anchors.fill: parent
                    active: card.turns && card.nbP > 0 && card.nbP < 1
                    sourceComponent: PageTurn {
                        source: leaf
                        edge: card.edge
                        progress: card.turnP
                    }
                }
                // The notebook's coil, over the sheet (and over the turning sheet: the wire runs through its slots).
                Loader {
                    anchors.fill: parent
                    active: card.isNotebook
                    sourceComponent: NotebookWire {
                        theme: Theme
                        geom: nb
                    }
                }
            }
        }
    }
}
