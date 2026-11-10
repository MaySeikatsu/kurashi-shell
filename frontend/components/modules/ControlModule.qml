import QtQuick
import Quickshell
import "../../core"
import ".."
import "../quick"
import "../island" as Isl

// A control of the control centre as a module of its own (W70, docs/ux/control-centre-modules.md): `wifi`, `bluetooth`,
// `focus`, `audio`, `mic`, `power`, `brightness`, `caffeine`, `nightlight`, `darkmode`, `airplane`. Its glance is the
// control's mark in a square as thick as the bar (QuickButton's target), and a short value after it where one is short
// (the battery's percent); its click opens its card (W71, I475 3), or flips its switch where the module's setting says so
// (`clickToggles`); its card is the control's page in the control centre (QuickNav); its menu is the module menu (I408).
// States, drawn from the control (Shōjiki): off (the mark outlined), on (filled), busy (dim, "…" in its name), failed (the
// error colour, a press retries), unavailable or held by a setting (dim, inert: a click opens the card that says why, or
// does nothing for a control with no page; the reason is its accessible name). Keys: its own tab stop — Enter opens its card
// (W71), Space does the click, the Menu key opens its menu. Bar fit (docs/ux/bar-fit.md): not elastic; compact is the mark alone.
// Ma: the control watches its document only while the host is live; nothing here runs a timer or an animation at rest.
ModuleBase {
    id: m
    // The concrete module sets its control (a quick/*Control) and what its glance draws.
    property var ctl: null
    property string glanceIcon: ctl ? ctl.icon : ""
    property string glanceGlyph: ctl ? ctl.glyph : ""
    // The short value after the mark ("" draws the mark alone). Dropped in the compact form and on a side bar.
    property string valueText: ""
    // W71 (I475 3): a click opens the control's card, where its switch, its options and why it cannot be used stand; the
    // module's own setting `quick.click.<clickKey>` (its menu, its card, Settings › Layout › Control centre) makes it the
    // switch instead. `defaultClick` is the schema's default, for the moment before the config document is there.
    property string clickKey: ctl ? ctl.mid : ""
    property string defaultClick: "card"
    readonly property var cfgValues: (Store.docs["config"] || ({})).values || ({})
    readonly property string clickMode: {
        var e = cfgValues["quick.click." + clickKey]
        return e && e.value !== undefined ? String(e.value) : defaultClick
    }
    readonly property bool clickToggles: clickMode === "switch" && !!ctl && ctl.toggles && ctl.req !== null
    // The wheel steps a level (sound, brightness): the module answers `wheeled(dy)` (a signal: a base function the module
    // redefined would be called as the base's own from here).
    property bool wheels: false
    signal wheeled(real dy)

    readonly property string cardPage: ctl ? ctl.page : ""
    // The control's card is up: its page, opened by this module (the card's state is runtime.ui's; the page QuickNav's).
    readonly property bool cardShown: cardPage !== "" && QuickNav.cardOpen && QuickNav.shown === cardPage
        && QuickNav.by === (ctl ? ctl.mid : "")
    readonly property bool inert: !ctl || ctl.inert
    readonly property bool lit: !!ctl && ctl.on && !inert && !ctl.failed
    readonly property bool showValue: valueText !== "" && !vertical && !compact

    // ---- the fit ----
    readonly property real boxW: thickness
    readonly property real valueW: showValueM.advanceWidth > 0 ? Math.ceil(showValueM.advanceWidth) + Theme.gap : 0
    TextMetrics { id: showValueM; text: m.valueText; font.pixelSize: Theme.fsCaption; font.weight: Theme.wBold; font.family: Theme.fam(text, Theme.families) }
    fullW: vertical ? thickness : boxW + (valueText !== "" ? valueW : 0)
    compactW: vertical ? thickness : boxW
    width: vertical ? thickness : boxW + (showValue ? valueW : 0)
    height: thickness
    slotHeights: [thickness]
    function geo() { return [[m.ctl ? m.ctl.mid : "control", m]] }

    // ---- what a press does ----
    // The card: the control's page in the control centre, or the control's own action when it has no page.
    function openCard() {
        if (cardPage === "") return
        Isl.IslandGeom.notePress(m.output, m.ctl.mid)
        QuickNav.open(cardPage, m.ctl.mid)
    }
    // (a hover's: opens, never closes; ModuleHost's `hoverSurface: "page"`)
    function showCard() {
        if (cardPage === "" || cardShown) return
        Isl.IslandGeom.notePress(m.output, m.ctl.mid)
        QuickNav.show(cardPage, m.ctl.mid)
    }
    function click() {
        if (!ctl) return
        if (clickToggles && !inert && !ctl.busy) { ctl.toggle(); return }
        if (cardPage !== "") openCard()
        else if (!inert) ctl.toggle()
    }
    // Enter on a host's tab stop (an edge group, the overflow): the card, else the switch (ModuleBase).
    function activate() {
        if (cardPage !== "") openCard()
        else click()
    }
    function openMenu() {
        Isl.IslandGeom.notePress(m.output, m.ctl.mid)
        Store.act("tray.menu.open", { id: "module:" + m.ctl.mid })
    }

    // ---- keys and a11y ----
    ownsFocus: true
    activeFocusOnTab: true
    Keys.onReturnPressed: m.activate()
    Keys.onEnterPressed: m.activate()
    Keys.onSpacePressed: m.click()
    Keys.onMenuPressed: m.openMenu()
    Accessible.role: Accessible.Button
    Accessible.checkable: !!ctl && ctl.toggles && ctl.req !== null
    Accessible.checked: lit
    // "Wi-Fi: Home", "Keep awake: No idle service", "Focus: Changing…".
    a11yName: ctl ? ctl.label + ": " + ctl.stateText : ""
    Accessible.name: a11yName

    // ---- the glance ----
    HoverHandler { id: hover }
    readonly property bool hot: cardShown || tap.pressed || hover.hovered
    Rectangle {
        x: 3
        y: 3
        width: m.width - 6
        height: m.height - 6
        radius: Theme.rSm
        // QuickButton's roles: the accent while its card is up, the raised container under the pointer.
        color: m.cardShown ? Theme.accent : (tap.pressed || hover.hovered ? Theme.containerHigh : "transparent")
        opacity: m.cardShown && (tap.pressed || hover.hovered) ? 0.85 : 1
    }
    Row {
        anchors.verticalCenter: parent.verticalCenter
        x: (m.boxW - mark.width) / 2
        spacing: (m.boxW - mark.width) / 2 + Theme.xs
        Icon {
            id: mark
            anchors.verticalCenter: parent.verticalCenter
            name: m.glanceIcon
            glyph: m.glanceGlyph
            filled: m.lit || m.cardShown
            color: m.cardShown ? Theme.fgOnAccent : m.ctl && m.ctl.failed ? Theme.error : m.inert ? Theme.dim : Theme.fg
            opacity: m.ctl && m.ctl.busy ? 0.45 : 1
            // Busy: three dots under the dimmed mark until the daemon answers (a tile's "connecting"; text, not a second
            // icon name: swapping the name while it settles its font loops).
            Text {
                visible: m.ctl !== null && m.ctl.busy
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.bottom
                anchors.topMargin: -6
                color: Theme.fg
                font.pixelSize: Theme.fsCaption
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                text: "…"
            }
        }
        Text {
            visible: m.showValue
            anchors.verticalCenter: parent.verticalCenter
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            color: m.cardShown ? Theme.fgOnAccent : m.inert ? Theme.dim : Theme.fg
            font.pixelSize: Theme.fsCaption
            font.weight: Theme.wBold
            font.family: Theme.fam(text, Theme.families)
            text: m.valueText
        }
    }
    // A left click is the module's; the host's right click opens the menu (ModuleHost, I408).
    TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton
        onTapped: m.click()
    }
    WheelHandler {
        enabled: m.wheels && !m.inert
        // (a wheel and a touchpad, as the workspaces' wheel takes them)
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => m.wheeled(event.angleDelta.y)
    }
    FocusRing {
        x: 3
        y: 3
        width: m.width - 6
        height: m.height - 6
        shown: m.activeFocus
        corner: Theme.rSm
        stroke: m.cardShown ? Theme.fgOnAccent : Theme.focusRing
    }
}
