import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "core"

// The web dock's card (docs/ux/webdock.md "Layout per edge", "Sites", "Motion", "Keyboard and a11y"; MODS.md "Web dock",
// "Host"; K40): one layer-shell surface at the dock's edge, mapped only while the shown pin is a web pin in extended
// mode, so hidden it draws nothing. The surface is the card plus `grace` px on every side but the strip's: the pointer's
// enter and leave of that margin are the card's `webdock.hover` reports, and the window's keyboard focus gained or lost
// its `webdock.engage`. The header holds the page's navigation and the dock's controls; the body holds one WebPage per
// pin in `keep`. The card sends `webdock.*` actions and draws what `mod.webdock` says; it never decides a mode or a pin.
// W21 (K42): the phone size is a phone seen from the front (PhoneFrame, the shell's own file through a link): the status
// row (the time, the page's host), the title in a pill under it, the page, and the header's controls as a bottom bar over
// the home indicator. The large size stays a plain card with the header on top.
PanelWindow {
    id: card

    // Set by shell.qml from `mod.webdock` and the host's objects.
    property var pins: []
    property var keepWeb: []           // ids of the web pins the host keeps loaded, most recent first
    property string shownId: ""
    property bool open: false          // mode extended and the shown pin a web pin
    property string edge: "right"
    property string size: "phone"      // phone | large
    property int strip: 56             // geometry.strip: the dock's strip, the card's margin from the edge
    property int phoneWidth: 412       // geometry.width
    property int largePct: 90          // geometry.large
    property int grace: 24             // geometry.grace: the hover margin on the sides away from the strip
    property string newTabs: "dock"    // new_tabs: dock (a link loads in the pin's view) | browser (the default browser)
    property bool engaged: false       // `engaged`: the dock holds the keyboard, so the page takes the first keystroke
    property string output: ""
    property var profiles: null        // Profiles (the view of each profile, the storage of each pin)
    property var report: null          // function(action, args): the reports and actions the card sends

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
    // The height the card is sized by: the usable height (the window, on a side). On a top or bottom edge the window has
    // the card's height, so the output's height stands in for it (a top bar there is not seen: a known gap).
    readonly property real basisH: sideways ? availH : screenH
    // Phone: `width` wide, as tall as twice that or the usable height allows, less a gap at each end (the lead's rule);
    // large: `large` % of the output's width, the usable height less a gap at each end.
    // The phone look: the phone size drawn as a phone (the large size is a plain card).
    readonly property bool phoneLook: !isLarge
    readonly property int cardW: isLarge ? Math.round(screenW * largePct / 100) : phoneWidth
    readonly property int cardH: Math.max(0, Math.round(isLarge ? basisH - 2 * gap : Math.min(2 * phoneWidth, basisH - 2 * gap)))
    // Where the card is in the window: a card on the right has its margin on its left (the window is card + margin wide),
    // one on the left on its right; a card on a top or bottom edge is centred across the usable width.
    readonly property int cardX: sideways ? (edge === "right" ? grace : 0) : Math.max(0, Math.round((availW - cardW) / 2))
    readonly property int cardY: edge === "top" ? 0 : edge === "bottom" ? grace
        : (isLarge ? gap : Math.max(0, Math.round((availH - cardH) / 2)))
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

    readonly property var activePage: pageFor(shownId, rep.count)
    readonly property var shownPin: pinById(shownId)
    readonly property string shownTarget: targetOf(shownId)
    readonly property string shownView: modeOf(shownId)
    // The home button shows once the page has left the pin's address (docs/ux/webdock.md "Layout per edge").
    readonly property bool homeShown: !!activePage && shownTarget !== "" && !activePage.atTarget
    // The theme's motion profile: `none` (reduced motion, the accessibility axis) fades instead of sliding.
    readonly property bool moves: (Theme.tokens["motion.profile"] || "calm") !== "none"
    readonly property bool springs: moves && Theme.springOn
    readonly property int slideMs: moves ? (Theme.stdMs > 0 ? 180 : 0) : Theme.quickMs
    // The distance the body slides out by, toward its edge; none when the motion is reduced.
    readonly property int away: !moves ? 0 : edge === "right" ? cardW : edge === "left" ? -cardW
        : edge === "bottom" ? cardH : -cardH

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
        if (open) mapped = true
        else {
            reportHover(false)
            menuOpen = false
        }
        slideAnim.to = open ? 0 : 1
        slideAnim.restart()
        if (open) Qt.callLater(card.focusPage)
    }
    // The dock asks for the keyboard (`engaged`) while the card is the front part: the page takes the first keystroke.
    onEngagedChanged: if (engaged && open) Qt.callLater(card.focusPage)
    onShownIdChanged: menuOpen = false
    onMenuOpenChanged: if (menuOpen && more.activeFocus) Qt.callLater(card.focusMenu)

    screen: screenObj
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "kurashi-webdock"
    // The window spans the card and its margin along the edge, and the usable area of the output across it: anchored to
    // the edge's two ends (the compositor stretches it), with exclusiveZone 0 (kept clear of a top bar, reserving nothing;
    // the default reserved the implicit size, 300 px, on the edge in the probe). A window of zero size is dropped by
    // Quickshell, so the other axis is the card's size, not 0.
    exclusiveZone: 0
    color: "transparent"
    anchors.top: edge !== "bottom"
    anchors.bottom: edge === "bottom" || sideways
    anchors.left: edge === "left" || !sideways
    anchors.right: edge === "right" || !sideways
    margins.top: edge === "top" ? strip : 0
    margins.bottom: edge === "bottom" ? strip : 0
    margins.left: edge === "left" ? strip : 0
    margins.right: edge === "right" ? strip : 0
    implicitWidth: sideways ? cardW + grace : 0
    implicitHeight: sideways ? 0 : cardH + grace
    // The input: the card and its margin only (the rest of the window is the desktop's, and it is transparent).
    mask: Region {
        x: card.inX
        y: card.inY
        width: card.mapped ? card.inW : 0
        height: card.mapped ? card.inH : 0
    }

    // Mapped (a layer surface) only while it shows: an unmapped card draws nothing (0 frames, Ma). The slide runs on
    // Theme.stdMs (180 ms) under the calm and lively profiles; under none it is the theme's quick duration (0: a cut).
    property real slide: 1
    property bool mapped: false
    visible: mapped
    Component.onCompleted: {
        syncViews()
        geometryLog()
        if (open) {
            mapped = true
            slide = 0
        }
    }
    NumberAnimation {
        id: slideAnim
        target: card
        property: "slide"
        // The rise is a spring (K42: the theme's overshoot, into the margin on the strip's side); the way out has none.
        duration: card.slideMs + (card.open && card.springs ? 60 : 0)
        easing.type: card.open && card.springs ? Easing.OutBack : Easing.OutCubic
        easing.overshoot: Theme.overshoot
        onStopped: if (!card.open) card.mapped = false
    }
    // The status row's time: the host has no svc.clock (its scope is mod.webdock, theme and i18n), so it keeps a minute
    // clock of its own, and only while the card is mapped (Ma).
    SystemClock {
        id: clock
        enabled: card.mapped && card.phoneLook
        precision: SystemClock.Minutes
    }
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
        Window.onActiveChanged: card.reportEngage(Window.active)
    }
    // Ctrl+L enters the header; the page is not told (it may take Ctrl+L for itself, but the card is the chrome's key).
    Shortcut {
        sequence: "Ctrl+L"
        enabled: card.open
        onActivated: card.focusHeader()
    }

    // The pages, one per web pin in `keep`: created when a pin is first kept, destroyed when it leaves `keep`.
    ListModel { id: viewModel }

    Item {
        id: body
        // Drawn once the window has its configured size (the first frame after a map has none, and no card then).
        visible: card.mapped && card.availW > 0 && card.availH > 0
        x: card.cardX + (card.sideways ? card.slide * card.away : 0)
        y: card.cardY + (card.sideways ? 0 : card.slide * card.away)
        width: card.cardW
        height: card.cardH
        opacity: card.moves ? 1 : 1 - card.slide

        PhoneFrame {
            id: phone
            visible: card.phoneLook
            anchors.fill: parent
            theme: Theme
            screenColor: Theme.container
            statusLeft: Text {
                height: phone.statusH
                verticalAlignment: Text.AlignVCenter
                text: Qt.formatTime(clock.date, "hh:mm")
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

        Rectangle {
            id: frame
            // Phone: the phone's screen (the status row and the home indicator are its own); large: the whole card.
            x: card.phoneLook ? phone.screen.x : 0
            y: card.phoneLook ? phone.screen.y : 0
            width: card.phoneLook ? phone.screen.width : parent.width
            height: card.phoneLook ? phone.screen.height : parent.height
            radius: card.phoneLook ? phone.screenRadius : Theme.rLg
            color: card.phoneLook ? "transparent" : Theme.container
            clip: true
            // Large: the page's corners follow the card's radius (I78): the layer is masked by the card's own rounded
            // shape. Phone: the page sits between the title and the bottom bar, clear of the screen's corners: no layer.
            layer.enabled: !card.phoneLook
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
                radius: Theme.rLg
                color: "white"
                layer.enabled: true
            }

            // Phone: the title in a pill under the status row (the page's title, or the pin's name), its load progress
            // along the pill's foot. Not a control: the press that gives the card the keyboard may land on it.
            Item {
                id: titleBar
                visible: card.phoneLook
                y: phone.statusH
                width: parent.width
                height: card.phoneLook ? 40 : 0
                Rectangle {
                    visible: Theme.shadowDy > 0
                    x: pill.x
                    y: pill.y + Theme.shadowDy
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
                    border.width: Theme.keycap ? Theme.outlineW : 0
                    border.color: Theme.line
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
                        anchors.bottomMargin: Theme.keycap ? Theme.outlineW : 0
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
                anchors.top: card.phoneLook ? undefined : parent.top
                anchors.bottom: card.phoneLook ? parent.bottom : undefined
                anchors.bottomMargin: card.phoneLook ? phone.homeH : 0
                anchors.left: parent.left
                anchors.right: parent.right
                height: card.phoneLook ? 40 : 36
                // Phone: the controls spread evenly across the bottom bar (the title is in its pill on top).
                readonly property int count: 7 + (card.homeShown ? 1 : 0)
                readonly property real spread: card.phoneLook
                    ? Math.max(0, (width - 2 * 12 - count * 26) / (count - 1)) : 0

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
                        id: back
                        glyph: "‹"
                        icon: "arrow_back_ios_new"
                        a11y: I18n.tr("webdock.nav.back")
                        enabled: !!(header.page && header.page.engine.canGoBack)
                        tipFn: card.tipFor
                        onClicked: header.page.engine.goBack()
                    }
                    HostButton {
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
                        id: home
                        visible: card.homeShown
                        glyph: "⌂"
                        icon: "home"
                        a11y: I18n.tr("webdock.nav.home")
                        tipFn: card.tipFor
                        onClicked: card.goHome()
                    }
                    HostButton {
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
                        id: viewToggle
                        shape: card.shownView === "mobile" ? "phone" : "desktop"
                        a11y: I18n.tr(card.shownView === "mobile" ? "webdock.host.view.mobile" : "webdock.host.view.desktop")
                        enabled: !!card.shownPin
                        tipFn: card.tipFor
                        onClicked: card.toggleView()
                    }
                    HostButton {
                        id: sizeToggle
                        shape: card.isLarge ? "wide" : "narrow"
                        a11y: I18n.tr(card.isLarge ? "webdock.host.size.large" : "webdock.host.size.phone")
                        tipFn: card.tipFor
                        onClicked: card.report("webdock.size", { size: card.isLarge ? "phone" : "large" })
                    }
                    HostButton {
                        id: more
                        glyph: "…"
                        icon: "more_horiz"
                        a11y: I18n.tr("webdock.nav.more")
                        tipFn: card.tipFor
                        onClicked: card.menuOpen = !card.menuOpen
                    }
                    HostButton {
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
                anchors.topMargin: card.phoneLook ? 6 : 0
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: card.phoneLook ? header.top : parent.bottom
                clip: true

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
                        mode: card.modeOf(pid)
                        active: card.open && pid === card.shownId
                        newTabsInDock: card.newTabs !== "browser"
                    }
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
                // Large: under the header; phone: over the bottom bar.
                anchors.top: card.phoneLook ? undefined : header.bottom
                anchors.bottom: card.phoneLook ? header.top : undefined
                anchors.right: parent.right
                anchors.topMargin: 4
                anchors.bottomMargin: 4
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
                y: card.phoneLook ? header.y - height - Theme.xs : header.height + Theme.xs
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
}
