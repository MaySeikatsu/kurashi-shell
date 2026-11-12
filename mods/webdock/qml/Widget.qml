import QtQuick
import Quickshell
import qs.core
import qs.components

// Bar widget of the web dock (`widget:webdock`, docs/ux/webdock.md "Keyboard and a11y"): one button that shows or hides
// the dock on the output this bar is on (`webdock.toggle {output}`). Its drawing is the dock's edge: an outline with the
// strip bar in it, lit while the dock is open, and a dot while the dock is kept open. Its name says the same in words.
// Visible = subscribed (Ma): a hidden bar holds no document.
Item {
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n
    id: w
    // A side bar hands this over: the same glyph, in the bar's 36 px.
    property bool vertical: false

    property bool live: visible
    Watch { doc: "mod.webdock"; active: w.live }

    readonly property var d: Store.docs["mod.webdock"] || ({})
    readonly property bool loaded: Store.docs["mod.webdock"] !== undefined
    readonly property bool available: d.available !== false
    readonly property bool open: (d.mode || "hidden") !== "hidden"
    readonly property bool pinned: d.pinned === true
    // The bar's window (Quickshell's QsWindow attached object) names the output the bar is on.
    readonly property string outName: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.name : ""

    // I495 (session 30; `bar_site`, `bar_playing`): the shown pin's image beside the icon, so it is plain what opens; and
    // while a page plays sound, its image and the page's title (a music site names its track there). The image is the
    // site's own (the host saves it), its letter where none is known yet.
    readonly property var pins: Array.isArray(d.pins) ? d.pins : []
    function pinOf(id) { for (var i = 0; i < pins.length; i++) if (pins[i].id === id) return pins[i]; return null }
    readonly property var playingPin: {
        if (d.bar_playing !== true) return null
        var s = pinOf(String(d.shown || ""))
        if (s && s.audible === true && s.page_title) return s
        for (var i = 0; i < pins.length; i++) if (pins[i].audible === true && pins[i].page_title) return pins[i]
        return null
    }
    readonly property var sitePin: playingPin !== null ? playingPin
        : d.bar_site === true && d.shown ? pinOf(String(d.shown)) : null
    readonly property bool showTitle: playingPin !== null && !vertical
    readonly property string stateWords: [
        open ? I18n.tr("webdock.dock.widget.open") : I18n.tr("webdock.dock.widget.closed"),
        pinned ? I18n.tr("webdock.dock.widget.pinned") : "",
        playingPin ? I18n.tr("webdock.dock.widget.playing").replace("{site}", String(playingPin.title || playingPin.id))
            .replace("{title}", String(playingPin.page_title))
            : sitePin ? I18n.tr("webdock.dock.widget.site").replace("{site}", String(sitePin.title || sitePin.id)) : ""
    ].filter(function (s) { return s !== "" }).join(", ")

    function toggle() {
        if (available) Store.act("webdock.toggle", outName !== "" ? { output: outName } : {})
    }
    // I482 (the user, session 28): a click opens the web dock's card with the page, as every module's click opens its
    // card (a second click closes it); the dock at the screen's edge is a middle click, its key or the command line.
    readonly property bool cardUp: String((Store.docs["runtime.ui"] || ({})).panel || "") === "mod:webdock:webdock"
    function card() {
        if (!available) return
        if (cardUp) Store.act("ui.close", {})
        else Store.act("mod.panel.open", { id: "webdock", panel: "webdock" })
    }

    // W66: a square as thick as the bar, as the quick settings button (the same room round the icon as its neighbours)
    implicitWidth: vertical ? Theme.barH : Theme.barH + (sitePin ? site.width + Theme.xs : 0)
        + (showTitle ? Math.min(220, title.implicitWidth) + Theme.gap : 0)
    implicitHeight: vertical ? Theme.barH + (sitePin ? site.height + Theme.xs : 0) : Theme.barH
    opacity: available ? 1 : Theme.staleOpacity
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: available ? I18n.tr("webdock.dock.widget") + ", " + stateWords : I18n.tr("webdock.dock.unavailable")

    Keys.onReturnPressed: w.card()
    Keys.onEnterPressed: w.card()
    Keys.onSpacePressed: w.card()

    // W66: a browser window (the web apps it opens), lit and filled while the dock is open, a dot while it is kept open;
    // the hand-drawn dock edge read as nothing in particular (session 26, the user). The icon font's own size, as every
    // bar icon.
    Icon {
        id: frameR
        x: (Theme.barH - width) / 2
        y: (Theme.barH - height) / 2
        name: "web_asset"
        glyph: "▭"
        filled: w.open
        color: w.open ? Theme.accent : Theme.fg
    }
    Rectangle {
        visible: w.pinned
        width: 5
        height: 5
        radius: 3
        color: Theme.accent
        x: frameR.x + frameR.width / 2 + frameR.font.pixelSize / 2 - 3
        y: frameR.y + frameR.height / 2 - frameR.font.pixelSize / 2 - 1
    }

    // The site: its image on a small key, or its letter.
    Item {
        id: site
        visible: w.sitePin !== null
        readonly property int side: Math.max(14, Math.round(Theme.barH * 0.62))
        width: side
        height: side
        x: w.vertical ? (Theme.barH - side) / 2 : Theme.barH
        y: w.vertical ? Theme.barH + Theme.xs : (Theme.barH - side) / 2
        readonly property string iconUrl: w.sitePin && w.sitePin.icon ? String(w.sitePin.icon) : ""
        Rectangle {
            anchors.fill: parent
            radius: Math.round(width * 0.3)
            color: Theme.containerHigh
            visible: siteImg.status !== Image.Ready
        }
        Image {
            id: siteImg
            anchors.fill: parent
            anchors.margins: 1
            source: site.iconUrl
            sourceSize: Qt.size(64, 64)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            smooth: true
        }
        Text {
            visible: siteImg.status !== Image.Ready
            anchors.centerIn: parent
            text: w.sitePin ? String(w.sitePin.title || w.sitePin.id || "?").charAt(0).toUpperCase() : ""
            color: Theme.fg
            font.pixelSize: Math.round(site.side * 0.62)
            font.weight: Theme.wBold
            font.family: Theme.fam(text, Theme.families)
        }
        // (playing: a small dot of the accent in its corner, the dock strip's own "loaded" mark)
        Rectangle {
            visible: w.playingPin !== null
            width: 5; height: 5; radius: 2.5
            color: Theme.accent
            x: parent.width - 3; y: -2
        }
    }
    Text {
        id: title
        visible: w.showTitle
        x: site.x + site.width + Theme.gap
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(220, implicitWidth)
        elide: Text.ElideRight
        text: w.playingPin ? String(w.playingPin.page_title) : ""
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        TextFx { onChange: true }
    }

    FocusRing {
        anchors.fill: parent
        shown: w.activeFocus
        corner: Theme.rSm
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => { if (mouse.button === Qt.MiddleButton) w.toggle(); else w.card() }
    }
}
