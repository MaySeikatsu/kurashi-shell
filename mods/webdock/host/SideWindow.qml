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

    readonly property bool onRight: !!place && place.side === "right"
    function screenFor(name) {
        var all = Quickshell.screens
        for (var i = 0; i < all.length; i++)
            if (all[i].name === name) return all[i]
        return all.length > 0 ? all[0] : null
    }
    screen: screenFor(place ? place.output : "")
    visible: open && !!place
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "kurashi-webdock-side"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    anchors.top: true
    anchors.left: !onRight
    anchors.right: onRight
    margins.top: place ? place.top : 0
    margins.left: place && !onRight ? place.inset : 0
    margins.right: place && onRight ? place.inset : 0
    implicitWidth: place ? Math.max(1, place.width) : 1
    implicitHeight: place ? Math.max(1, place.height) : 1

    // Test only (KURASHI_WEBDOCK_DEBUG=1, mods/webdock/test/test-sidebar.sh): the window, the page in it, its frames.
    function geometryLog() {
        if (!debugLog || !visible) return
        var pg = side.page
        console.log("webdock-debug side " + (pin ? pin.id : "-") + " win " + Math.round(area.width) + " " + Math.round(area.height)
            + " page " + (pg && pg.parent === slotItem ? Math.round(slotItem.x) + " " + Math.round(slotItem.y) + " "
                + Math.round(pg.width) + " " + Math.round(pg.height) : "none")
            + " place " + (place ? place.output + " " + place.side + " " + place.inset + " " + place.top + " " + place.width
                + " " + place.height : "-"))
    }
    onVisibleChanged: if (debugLog) console.log("webdock-debug side " + (visible ? "shown" : "hidden"))
    onPageChanged: geometryLog()
    Connections {
        target: side.debugLog ? frame.Window.window : null
        function onFrameSwapped() { console.log("webdock-debug side frame") }
    }

    function hostOf(u) {
        var m = /^[a-z][a-z0-9+.-]*:\/\/([^\/?#:]+)/i.exec(String(u || ""))
        return m ? m[1] : ""
    }

    Item {
        id: area
        anchors.fill: parent
        onWidthChanged: side.geometryLog()
        onHeightChanged: side.geometryLog()

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
