import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "core"

// The web dock's page in a sidebar (W30; docs/ux/webdock.md "In the sidebar"): a layer window over the sidebar panel's
// page area, where `mod.webdock.sidebar.place` says it rests — on that output, anchored to the usable area's top and to
// the sidebar's side, `inset` px in from that edge, `top` px down, `width` × `height`: the same anchoring as the sidebar's
// own window (top + side, exclusive zone 0), so the compositor puts both in the same place. Not phone shaped: a slim
// navigation row on top and the page under it, filling the area. The page is the same WebPage the edge card shows (it is
// moved into `slot` while the sidebar shows its pin, one page per pin, K38). Mapped only while the sidebar rests open on
// a site: closed, sliding or scrolled away, it is unmapped and draws nothing (Ma). The Overlay layer keeps it above the
// sidebar's Top-layer window. It sends no hover or engage report: the edge dock's state machine is not its business.
// W72 (`cardRole: true`, docs/ux/webdock.md "In the bar's card"): the same window over the bar card's well, where
// `mod.webdock.card.place` says it rests — on that output, `x`, `y` px from its top-left corner (zones ignored, as the
// shell's Stage), `width` × `height`; above the Stage's Overlay window (mapped after it). There it reports the pointer in
// it and a press in it (`webdock.card_page`: the shell holds the card while the pointer is on the page and makes it the
// user's on a press), Esc closes the card (`webdock.card_close`), "Show at the edge" moves the pin to the edge card, and
// the keyboard asked for the page (`card.focus`) is taken once. It fades in once mapped (a cut under reduced motion).
PanelWindow {
    id: side

    property var place: null           // mod.webdock.sidebar.place
    property bool open: false          // the sidebar rests open on a web pin
    property var pin: null             // that pin (its document entry)
    property var page: null            // its WebPage, once the card's Repeater has it
    property string view: "mobile"     // the pin's profile view
    property var report: null
    readonly property Item slot: slotItem
    readonly property bool debugLog: Quickshell.env("KURASHI_WEBDOCK_DEBUG") === "1"
    // W72: the bar card's window (`place` is `{output, x, y, width, height}`), the dock's edge (the way out's icon), and the
    // focus counter of `mod.webdock.card`.
    property bool cardRole: false
    property string dockEdge: "right"
    property int focusAsks: 0
    readonly property string tag: cardRole ? "card" : "side"

    readonly property bool onRight: !cardRole && !!place && place.side === "right"
    function screenFor(name) {
        var all = Quickshell.screens
        for (var i = 0; i < all.length; i++)
            if (all[i].name === name) return all[i]
        return all.length > 0 ? all[0] : null
    }
    screen: screenFor(place ? place.output : "")
    visible: open && !!place
    color: "transparent"
    exclusionMode: cardRole ? ExclusionMode.Ignore : ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: cardRole ? "kurashi-webdock-card" : "kurashi-webdock-side"
    // (W72: the card's window asks for the keyboard once when the page is asked for it; a click gives it on demand)
    WlrLayershell.keyboardFocus: asksKeys ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    anchors.top: true
    anchors.left: !onRight
    anchors.right: onRight
    margins.top: !place ? 0 : (cardRole ? place.y : place.top)
    margins.left: !place || onRight ? 0 : (cardRole ? place.x : place.inset)
    margins.right: place && onRight ? place.inset : 0
    implicitWidth: place ? Math.max(1, place.width) : 1
    implicitHeight: place ? Math.max(1, place.height) : 1

    // Test only (KURASHI_WEBDOCK_DEBUG=1, mods/webdock/test/test-sidebar.sh, test-card.sh): the window, the page in it,
    // its frames. (A card's place reads `<output> <x> <y> <w> <h>`.)
    function geometryLog() {
        if (!debugLog || !visible) return
        var pg = side.page
        console.log("webdock-debug " + tag + " " + (pin ? pin.id : "-") + " win " + Math.round(area.width) + " "
            + Math.round(area.height)
            + " page " + (pg && pg.parent === slotItem ? Math.round(slotItem.x) + " " + Math.round(slotItem.y) + " "
                + Math.round(pg.width) + " " + Math.round(pg.height) : "none")
            + " place " + (!place ? "-" : cardRole ? place.output + " " + place.x + " " + place.y + " " + place.width + " "
                + place.height : place.output + " " + place.side + " " + place.inset + " " + place.top + " " + place.width
                + " " + place.height))
    }
    onVisibleChanged: {
        if (debugLog) console.log("webdock-debug " + tag + " " + (visible ? "shown" : "hidden"))
        if (!cardRole) return
        // W72: the page fades in once the card rests (a cut under reduced motion); unmapped, the pointer and the keyboard
        // are out of it, whatever the compositor sent last.
        if (visible) {
            fade.stop()
            area.opacity = side.moves ? 0 : 1
            if (side.moves) fade.start()
        } else {
            side.reportPage(false, false)
            side.pulseSpent = true
            side.wantKeys = false
        }
    }
    onPageChanged: geometryLog()
    onPinChanged: geometryLog()
    Connections {
        target: side.debugLog ? frame.Window.window : null
        function onFrameSwapped() { console.log("webdock-debug " + side.tag + " frame") }
    }

    // ---- W72: the bar card's window ----
    readonly property string motionProfile: Theme.tokens["motion.profile"] || "calm"
    readonly property bool moves: motionProfile !== "none" && motionProfile !== "reduced" && Theme.quickMs > 0
    NumberAnimation {
        id: fade
        target: area
        property: "opacity"
        from: 0
        to: 1
        duration: Theme.quickMs
        easing.type: Easing.OutCubic
    }
    // The pointer and the keyboard in the window, on change only.
    property bool hoverSent: false
    property bool engagedSent: false
    function reportPage(hover, engaged) {
        if (!cardRole || (hover === hoverSent && engaged === engagedSent)) return
        hoverSent = hover
        engagedSent = engaged
        if (report) report("webdock.card_page", { hover: hover, engaged: engaged })
    }
    function closeCard() { if (cardRole && report) report("webdock.card_close", {}) }
    function toEdge() {
        if (!report || !pin) return
        report("webdock.open", { pin: pin.id, output: place ? place.output : "" })
        closeCard()
    }
    // The keyboard asked for the page (Tab past the card's keys): the window asks for it exclusively until it has it, at
    // most a second (WebCard's pulse), then on demand again.
    property bool winActive: false
    property bool pulseSpent: true
    // The user is using the page: a press in it, or the keyboard asked for it — reported as `engaged` (the shell makes the
    // card the user's, as a press in the card does). Not the window's keyboard focus alone: a compositor may hand a freshly
    // mapped on-demand layer the keyboard without anyone using it, and one with no keyboard device sends no focus at all.
    property bool wantKeys: false
    function pressed() {
        if (!cardRole) return
        if (debugLog) console.log("webdock-debug card press")
        wantKeys = true
        // (a compositor that does not hand an on-demand layer the keyboard on a click gets the pulse)
        if (!winActive) pulseSpent = false
        reportPage(hoverSent, true)
    }
    readonly property bool asksKeys: cardRole && visible && !winActive && !pulseSpent
    onAsksKeysChanged: if (asksKeys) pulseTimer.restart(); else pulseTimer.stop()
    Timer { id: pulseTimer; interval: 1000; onTriggered: side.pulseSpent = true }
    property int focusSeen: -1
    onFocusAsksChanged: {
        if (cardRole && focusSeen >= 0 && focusAsks > focusSeen && visible) {
            wantKeys = true
            pulseSpent = false
            if (winActive && page) page.engine.forceActiveFocus()
            reportPage(hoverSent, true)
        }
        focusSeen = focusAsks
    }
    Component.onCompleted: focusSeen = focusAsks
    // The edge the way out points to (the dock's edge).
    readonly property string edgeIcon: dockEdge === "left" ? "left_panel_open"
        : (dockEdge === "right" ? "right_panel_open" : "dock_to_bottom")

    function hostOf(u) {
        var m = /^[a-z][a-z0-9+.-]*:\/\/([^\/?#:]+)/i.exec(String(u || ""))
        return m ? m[1] : ""
    }

    Item {
        id: area
        anchors.fill: parent
        onWidthChanged: side.geometryLog()
        onHeightChanged: side.geometryLog()
        // W72: the card's window reports the pointer and the keyboard in it (handlers on top of the page, passive: the page
        // gets every event). Its keyboard focus gained is the page's.
        Item {
            anchors.fill: parent
            z: 100
            HoverHandler {
                enabled: side.cardRole
                onHoveredChanged: side.reportPage(hovered, side.wantKeys)
            }
            PointHandler {
                enabled: side.cardRole
                acceptedButtons: Qt.AllButtons
                onActiveChanged: if (active) side.pressed()
            }
        }
        Window.onActiveChanged: {
            if (side.debugLog) console.log("webdock-debug " + side.tag + " keyboard " + (Window.active ? "in" : "out"))
            side.winActive = Window.active
            if (Window.active) side.pulseSpent = true
            side.reportPage(side.hoverSent, side.wantKeys)
            if (Window.active && side.cardRole && side.page && !nav.activeFocus) side.page.engine.forceActiveFocus()
        }
        // W72: Esc closes the bar card, wherever the keyboard is in its window (a popover's Esc, as the Stage's own keys).
        // A shortcut, ahead of the page: QtWebEngine 6.11 hands no unhandled Esc back to its parents (measured on niri),
        // so a site's own Esc (its dialog) is not reached here — at the edge and in the sidebar the page keeps it.
        Shortcut {
            sequence: "Escape"
            enabled: side.cardRole && side.visible
            onActivated: side.closeCard()
        }

        // The area's frame: the well's colour and radius (the panel draws the same well under it), the page masked to it.
        Rectangle {
            id: frame
            anchors.fill: parent
            radius: Theme.rLg
            color: Theme.containerHigh
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: frameMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }
            Rectangle {
                id: frameMask
                visible: false
                anchors.fill: parent
                radius: Theme.rLg
                color: "white"
                layer.enabled: true
            }

            // Navigation: back, forward, the title (the page's, or the pin's), reload, the view, the browser.
            Item {
                id: nav
                width: parent.width
                height: 36
                readonly property var engine: side.page ? side.page.engine : null
                Keys.onEscapePressed: event => {
                    if (side.page) side.page.engine.forceActiveFocus()
                    event.accepted = true
                }
                Row {
                    id: navL
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    HostButton {
                        glyph: "‹"
                        icon: "arrow_back_ios_new"
                        a11y: I18n.tr("webdock.nav.back")
                        enabled: !!(nav.engine && nav.engine.canGoBack)
                        onClicked: nav.engine.goBack()
                    }
                    HostButton {
                        glyph: "›"
                        icon: "arrow_forward_ios"
                        a11y: I18n.tr("webdock.nav.forward")
                        enabled: !!(nav.engine && nav.engine.canGoForward)
                        onClicked: nav.engine.goForward()
                    }
                }
                Text {
                    anchors.left: navL.right
                    anchors.leftMargin: 6
                    anchors.right: navR.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: nav.engine && nav.engine.title ? nav.engine.title : (side.pin ? side.pin.title : "")
                    color: Theme.fg
                    font.pixelSize: Theme.fsLabel
                    font.weight: Theme.wBold
                    font.family: Theme.fam(text, Theme.families)
                }
                Row {
                    id: navR
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    HostButton {
                        visible: !!side.page && !side.page.atTarget
                        glyph: "⌂"
                        icon: "home"
                        a11y: I18n.tr("webdock.nav.home")
                        onClicked: if (side.pin) side.page.engine.url = side.pin.target
                    }
                    HostButton {
                        glyph: "↻"
                        icon: "refresh"
                        a11y: I18n.tr("webdock.nav.reload")
                        enabled: !!nav.engine
                        onClicked: nav.engine.reload()
                    }
                    HostButton {
                        shape: side.view === "mobile" ? "phone" : "desktop"
                        a11y: I18n.tr(side.view === "mobile" ? "webdock.host.view.mobile" : "webdock.host.view.desktop")
                        enabled: !!side.pin
                        onClicked: if (side.report) side.report("webdock.view",
                            { pin: side.pin.id, view: side.view === "mobile" ? "desktop" : "mobile" })
                    }
                    // W72: the way out to the larger place: the pin at the edge (its large size); the card closes.
                    HostButton {
                        visible: side.cardRole
                        glyph: "⇥"
                        icon: side.edgeIcon
                        a11y: I18n.tr("webdock.side.at_edge")
                        enabled: !!side.pin
                        onClicked: side.toEdge()
                    }
                    HostButton {
                        glyph: "↗"
                        icon: "open_in_new"
                        a11y: I18n.tr("webdock.open_browser")
                        enabled: !!nav.engine
                        onClicked: if (side.report) side.report("webdock.open_external", { url: String(nav.engine.url) })
                    }
                }
                // The load progress along the row's foot.
                Rectangle {
                    anchors.bottom: parent.bottom
                    height: 2
                    width: nav.engine ? parent.width * nav.engine.loadProgress / 100 : 0
                    visible: !!nav.engine && nav.engine.loading
                    color: Theme.accent
                }
            }

            // Blocked permissions of the pin: one chip each, until the next load (brief "Sites").
            Row {
                id: chips
                anchors.top: nav.bottom
                anchors.left: parent.left
                anchors.leftMargin: 8
                spacing: 6
                visible: !!side.pin && !!side.pin.blocked && side.pin.blocked.length > 0
                height: visible ? 24 : 0
                Repeater {
                    model: side.pin && side.pin.blocked ? side.pin.blocked : []
                    delegate: HostChip {
                        required property string modelData
                        text: I18n.tr("webdock.blocked." + modelData)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // The page: the WebPage moves in here (the card's Repeater owns it).
            Item {
                id: slotItem
                anchors.top: chips.visible ? chips.bottom : nav.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true
                onWidthChanged: side.geometryLog()
                onHeightChanged: side.geometryLog()

                // The skeleton until the first paint: no white flash.
                Rectangle {
                    anchors.fill: parent
                    z: 2
                    color: Theme.containerHigh
                    visible: !side.page || !side.page.painted
                    Text {
                        anchors.centerIn: parent
                        text: I18n.tr(Store.live ? "webdock.loading" : "webdock.host.starting")
                        color: Theme.dim
                        font.pixelSize: Theme.fsLabel
                        font.family: Theme.fam(text, Theme.families)
                    }
                }
                // A load that failed: the code, retry, the browser.
                Column {
                    anchors.centerIn: parent
                    z: 3
                    spacing: Theme.gap
                    visible: !!side.page && !!side.page.loadError
                    Text {
                        width: slotItem.width - 2 * Theme.pad
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        text: I18n.tr("webdock.error.load") + "\n" + I18n.tr("webdock.error.code").replace("{code}",
                            side.page && side.page.loadError ? String(side.page.loadError.code) : "")
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
                            onClicked: side.page.engine.reload()
                        }
                        HostButton {
                            label: I18n.tr("webdock.open_browser")
                            onClicked: if (side.report) side.report("webdock.open_external", { url: String(side.page.engine.url) })
                        }
                    }
                }
                // The renderer stopped: reload brings the page back.
                Column {
                    anchors.centerIn: parent
                    z: 3
                    spacing: Theme.gap
                    visible: !!side.pin && side.pin.error === "webdock.error.crashed"
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.tr("webdock.error.crashed")
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                    }
                    HostButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        label: I18n.tr("webdock.nav.reload")
                        primary: true
                        onClicked: if (side.page) side.page.engine.reload()
                    }
                }
                // A sign-in popup is a sheet over the page: its close button is the way back.
                HostButton {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 4
                    z: 4
                    visible: !!side.page && !!side.page.sheet
                    glyph: "×"
                    a11y: I18n.tr("webdock.sheet.close")
                    onClicked: side.page.closeSheet()
                }
            }
        }
    }
}
