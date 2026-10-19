import QtQuick
import Quickshell
import Quickshell.Wayland
import "core"

// The web dock's card (docs/ux/webdock.md "Card"; MODS.md "Web dock", Host): one layer-shell surface at the dock's
// edge, mapped only while the shown pin is a web pin in extended mode, so hidden it draws nothing. The header holds
// the page's navigation and the dock's controls; the body holds one WebPage per pin in `keep`. The card sends
// `webdock.*` actions and draws what `mod.webdock` says; it never decides a mode or a pin (the daemon does).
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
    property string output: ""
    property var profiles: null        // Profiles (WebPage profiles and the mobile/desktop view of each)
    property var report: null          // function(action, args): the reports and actions the card sends

    readonly property int gap: Theme.gap
    readonly property bool sideways: edge === "left" || edge === "right"
    readonly property bool isLarge: size === "large"
    readonly property var screenObj: screenFor(output)
    readonly property real outW: screenObj ? screenObj.width : 1920
    readonly property real outH: screenObj ? screenObj.height : 1080
    // Phone: `width` wide, as tall as twice that or the output allows; large: `large` % of the output's width, full height.
    readonly property int cardW: isLarge ? Math.round(outW * largePct / 100) : phoneWidth
    readonly property int cardH: isLarge ? Math.round(outH - 2 * gap) : Math.min(2 * phoneWidth, Math.round(outH - 2 * gap))
    readonly property int away: edge === "right" ? cardW : edge === "left" ? -cardW : edge === "bottom" ? cardH : -cardH
    readonly property var activePage: pageFor(shownId, rep.count)
    readonly property var shownPin: pinById(shownId)

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
    function openBrowser() {
        if (activePage && report) report("webdock.open_external", { url: String(activePage.engine.url) })
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
        slideAnim.to = open ? 0 : 1
        slideAnim.restart()
        if (open) Qt.callLater(function () { if (card.activePage) card.activePage.engine.forceActiveFocus() })
    }

    screen: screenObj
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "kurashi-webdock"
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    implicitWidth: cardW
    implicitHeight: cardH
    anchors.top: edge !== "bottom"
    anchors.bottom: edge === "bottom"
    anchors.left: edge !== "right"
    anchors.right: edge === "right"
    margins.top: edge === "top" ? strip : sideways ? (isLarge ? gap : Math.round((outH - cardH) / 2)) : 0
    margins.bottom: edge === "bottom" ? strip : 0
    margins.left: edge === "left" ? strip : (edge === "right" ? 0 : Math.max(0, Math.round((outW - cardW) / 2)))
    margins.right: edge === "right" ? strip : 0

    // Mapped (a layer surface) only while it shows: an unmapped card draws nothing (0 frames, Ma). The slide runs on
    // Theme.stdMs (180 ms), instantly under the motion profile none; a card that slid out is unmapped at its end.
    property real slide: 1
    property bool mapped: false
    visible: mapped
    readonly property int slideMs: Theme.stdMs > 0 ? 180 : 0
    Component.onCompleted: {
        syncViews()
        if (open) {
            mapped = true
            slide = 0
        }
    }
    NumberAnimation {
        id: slideAnim
        target: card
        property: "slide"
        duration: card.slideMs
        easing.type: Easing.OutCubic
        onStopped: if (!card.open) card.mapped = false
    }

    // The pages, one per web pin in `keep`: created when a pin is first kept, destroyed when it leaves `keep`.
    ListModel { id: viewModel }

    Item {
        id: body
        width: card.cardW
        height: card.cardH
        x: card.sideways ? card.slide * card.away : 0
        y: card.sideways ? 0 : card.slide * card.away

        Rectangle {
            id: frame
            anchors.fill: parent
            radius: Theme.rLg
            color: Theme.container
            clip: true

            Item {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 36

                readonly property var page: card.activePage
                readonly property string title: (page && page.engine.title) ? page.engine.title
                    : (card.shownPin ? card.shownPin.title : "")

                HostButton {
                    id: back
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "‹"
                    a11y: I18n.tr("webdock.nav.back")
                    enabled: !!(header.page && header.page.engine.canGoBack)
                    onClicked: header.page.engine.goBack()
                }
                Text {
                    id: titleText
                    anchors.left: back.right
                    anchors.leftMargin: 6
                    anchors.right: controls.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: header.title
                    color: Theme.fg
                    font.pixelSize: Theme.fsLabel
                    font.family: Theme.fam(text, Theme.families)
                }
                Row {
                    id: controls
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    HostButton {
                        glyph: "↻"
                        a11y: I18n.tr("webdock.nav.reload")
                        enabled: !!header.page
                        onClicked: header.page.engine.reload()
                    }
                    WebSegment {
                        anchors.verticalCenter: parent.verticalCenter
                        keyA: "mobile"
                        labelA: I18n.tr("webdock.view.mobile")
                        keyB: "desktop"
                        labelB: I18n.tr("webdock.view.desktop")
                        current: card.shownPin && card.shownPin.view === "mobile" ? "mobile" : "desktop"
                        onPicked: key => card.report("webdock.view", { pin: card.shownId, view: key })
                    }
                    WebSegment {
                        anchors.verticalCenter: parent.verticalCenter
                        keyA: "phone"
                        labelA: I18n.tr("webdock.size.phone")
                        keyB: "large"
                        labelB: I18n.tr("webdock.size.large")
                        current: card.size
                        onPicked: key => card.report("webdock.size", { size: key })
                    }
                    HostButton {
                        glyph: "↗"
                        a11y: I18n.tr("webdock.open_browser")
                        enabled: !!header.page
                        onClicked: card.openBrowser()
                    }
                    HostButton {
                        glyph: "×"
                        a11y: I18n.tr("webdock.nav.collapse")
                        onClicked: card.report("webdock.collapse", {})
                    }
                }
            }

            // Blocked permissions of the shown pin: one chip each, until the next load (brief "Sites").
            Row {
                id: chips
                anchors.top: header.bottom
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

            // The page's load progress, under the header.
            Rectangle {
                anchors.top: header.bottom
                anchors.left: parent.left
                height: 2
                width: card.activePage ? parent.width * card.activePage.engine.loadProgress / 100 : 0
                visible: !!card.activePage && card.activePage.engine.loading
                color: Theme.accent
            }

            Item {
                id: pane
                anchors.top: chips.visible ? chips.bottom : header.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
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
        }
    }
}
