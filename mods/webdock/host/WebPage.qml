import QtQuick
import QtWebEngine

// One pin's page in the card's body (MODS.md "Web dock": one view per pin in `keep`). It exists while its pin is in
// `keep` (the Repeater creates it when the pin is first shown and destroys it when the pin leaves `keep`, which
// reports `unloaded`). The card draws only the shown page; the others are hidden and Frozen unless audible or awake (W73).
Item {
    id: page

    property string pinId: ""
    property string target: ""
    property var profile: null
    property var report: null
    // I495 (session 30, the user: the strip and the bar show the site's own image, its letter only where none is known):
    // the page's icon, saved once per icon to `iconDir/<pin>.png` (the daemon's icon cache: it accepts nothing else) and
    // reported with the load, so the shell — another process, without the engine's favicon provider — can show it.
    property string iconDir: ""
    property bool siteIcons: true
    property string savedIcon: ""
    // (session 31: a grab draws the item in its window, so it works only while that window is shown — the page often
    // loads in a hidden one, and the one try on load failed without a word; the user saw no icon at all. It is tried
    // again whenever the page is shown, and every few seconds while it is shown and has none saved.)
    function saveIcon() {
        var w = favicon.Window.window
        if (debugLog) console.log("webdock-debug icon " + pinId + " dir=" + (iconDir !== "") + " icon=" + String(web.icon)
            + " status=" + favicon.status + " win=" + (w ? w.visible : "none") + " grabbing=" + grabbing + " saved=" + savedIcon)
        if (iconDir === "" || pinId === "" || favicon.status !== Image.Ready || String(web.icon) === savedIcon) return
        if (!w || !w.visible || grabbing) return
        var at = String(web.icon)
        grabbing = favicon.grabToImage(function (res) {
            page.grabbing = false
            var path = page.iconDir + "/" + page.pinId.replace(/[^A-Za-z0-9_.-]/g, "_") + ".png"
            var saved = res.saveToFile(path)
            if (page.debugLog) console.log("webdock-debug icon saved " + page.pinId + " " + path + " " + saved)
            if (saved) {
                page.savedIcon = at
                if (page.report) page.report("webdock.host.loaded", { pin: page.pinId, icon: path })
            }
        }, Qt.size(64, 64))
    }
    property bool grabbing: false
    readonly property bool iconOwed: iconDir !== "" && String(web.icon) !== "" && String(web.icon) !== savedIcon
    Connections {
        target: page.iconOwed && favicon.Window.window ? favicon.Window.window : null
        function onVisibleChanged() { Qt.callLater(page.saveIcon) }
    }
    Timer { interval: 3000; repeat: true; running: page.iconOwed && page.active; onTriggered: page.saveIcon() }
    // (drawn, at an opacity the eye cannot see, so it can be grabbed; only while it holds an icon)
    Image {
        id: favicon
        z: -1
        width: 32
        height: 32
        opacity: 0.01
        visible: String(web.icon) !== ""
        source: web.icon
        sourceSize: Qt.size(64, 64)
        fillMode: Image.PreserveAspectFit
        smooth: true
        onStatusChanged: if (status === Image.Ready) Qt.callLater(page.saveIcon)
    }
    // The profile's view: "mobile" or "desktop". A change reloads the page (the user agent is sent with a request).
    property string mode: ""
    property bool active: false
    // new_tabs (K40): a link for a new tab or window loads in this page (true) or goes to the browser (false).
    property bool newTabsInDock: true
    // W73: the page stays Active though hidden and silent — the pin's `awake`, `audible` or `background` in mod.webdock
    // (the daemon's grace after a sound, a pin that keeps running).
    property bool awake: false

    // W76 (docs/ux/webdock.md "Round three"): the pin's menu asks for a reload (`reload` on the pin, a counter: each new
    // value reloads once; the value the page is made with is the baseline), and the page tells the daemon where it is
    // (`webdock.host.url`, on each change of address only), so the menu can offer "Update pin to this page".
    property int reloadAsks: 0
    property int reloadSeen: -1
    onReloadAsksChanged: {
        if (reloadSeen >= 0 && reloadAsks > reloadSeen && web.url.toString() !== "") web.reload()
        reloadSeen = reloadAsks
    }
    Connections {
        target: web
        function onUrlChanged() {
            var u = web.url.toString()
            if (u !== "" && u !== "about:blank" && page.report && page.pinId !== "") page.report("webdock.host.url", { pin: page.pinId, url: u })
        }
    }

    // What the card draws: the first paint (the skeleton goes), a failed load (code and text), a popup sheet.
    property bool painted: false
    property var loadError: null
    property var sheet: null
    readonly property var engine: web
    // The page is at the pin's address, the fragment and a trailing slash aside: the header's home button is off then.
    readonly property bool atTarget: bare(web.url) === bare(target)

    anchors.fill: parent
    // Only the shown pin's page is drawn — its sign-in sheet included (a sheet stayed over the next pin otherwise).
    visible: active

    // The address without its fragment and its trailing slash (docs/ux/webdock.md "Layout per edge", the home rule).
    function bare(u) {
        var s = String(u)
        var h = s.indexOf("#")
        if (h >= 0) s = s.substring(0, h)
        while (s.length > 0 && s.charAt(s.length - 1) === "/") s = s.substring(0, s.length - 1)
        return s
    }

    // The pin's address loads when the page is made, and again when the pin's target moves to another address (a
    // settings edit). The view's `url` is not bound: the header navigates it, which would drop a binding.
    Component.onCompleted: {
        reloadSeen = reloadAsks
        // (W76: a "+" page starts blank — an engine never given an address did not load the first one it was given later)
        web.url = target !== "" ? target : "about:blank"
        // W30: the page lives in the card's pane (`home`) or, while the sidebar shows its pin, in the sidebar window's
        // slot (`sideHost`). Bound here, after the Repeater has set the parent it creates the page with.
        parent = Qt.binding(function () { return page.sideHost !== null ? page.sideHost : page.home })
    }
    // W30: where the page is drawn (see above). A move between the two windows keeps the page (no reload).
    property Item home: null
    property Item sideHost: null
    // Test only (KURASHI_WEBDOCK_DEBUG=1): the page drawn or frozen.
    onActiveChanged: {
        if (debugLog) console.log("webdock-debug page " + pinId + " " + (active ? "active" : "frozen"))
        // (I495: a page shown again tries its icon)
        if (active) Qt.callLater(saveIcon)
        else if (pageMenu.open) pageMenu.close()
    }
    property bool debugLog: false
    // (W73: the engine's state names: Active, Frozen, Discarded)
    function lifeLog(what) {
        if (!debugLog) return
        var n = ["Active", "Frozen", "Discarded"]
        console.log("webdock-debug life " + pinId + " " + what + ": state " + n[web.lifecycleState] + " recommended "
            + n[web.recommendedState] + " audible " + web.recentlyAudible + " visible " + web.visible)
    }
    onTargetChanged: {
        if (debugLog) console.log("webdock-debug target " + pinId + " " + target + " at " + web.url)
        if (target !== "" && !atTarget) web.url = target
    }

    onModeChanged: {
        if (lastMode !== "" && mode !== lastMode)
            Qt.callLater(function () { if (web.url.toString() !== "") web.reload() })
        lastMode = mode
    }
    property string lastMode: ""

    PrivateView {
        id: web
        anchors.fill: parent
        pinId: page.pinId
        siteIcons: page.siteIcons
        report: page.report
        profile: page.profile
        newTabsInDock: page.newTabsInDock
        visible: page.active
        focus: page.active
        // Hidden pages are Frozen (no timers, no painting) unless they play audio (brief "Fit and constraints").
        // (W72: the engine's own recommendation — Active while it is visible or audible — so the freeze comes once the
        // engine has seen the hide; set at the hide itself it was refused, "page is visible", and the page stayed Active.
        // Never Discarded here: the dock's own rules unload a page.)
        // W73 (I488, docs/ux/webdock.md "Background pages"): and Active while the daemon says the page stays awake — in
        // its grace after a sound, or a background pin. Measured: the engine recommends Frozen for a page hidden in a
        // silence (a pause, the gap between two tracks) and the frozen player never starts its next track.
        lifecycleState: web.recommendedState === WebEngineView.LifecycleState.Active || web.recentlyAudible
            || (page.active && web.visible) || page.awake
            ? WebEngineView.LifecycleState.Active : WebEngineView.LifecycleState.Frozen

        onLoadingChanged: request => {
            if (request.status === WebEngineView.LoadStartedStatus) {
                page.loadError = null
            } else if (request.status === WebEngineView.LoadSucceededStatus) {
                page.painted = true
                if (page.report) page.report("webdock.host.loaded", { pin: page.pinId })
            } else if (request.status === WebEngineView.LoadFailedStatus) {
                page.painted = true
                page.loadError = { code: request.errorCode, text: request.errorString }
            }
        }
        onRenderProcessTerminated: (status, code) => page.painted = true
        // Test only (KURASHI_WEBDOCK_DEBUG=1, W73): the engine's lifecycle, its recommendation and the sound.
        onLifecycleStateChanged: page.lifeLog("lifecycle")
        onRecommendedStateChanged: page.lifeLog("recommended")
        onRecentlyAudibleChanged: function () { page.lifeLog("audible") }
        onVisibleChanged: page.lifeLog("visible")
        onSheetRequested: request => page.openSheet(request)
        // W82: the shell's menu, not the engine's (docs/ux/context-menus.md)
        onContextMenuRequested: request => pageMenu.show(web, request)
    }

    // W82 (docs/ux/context-menus.md, `page:<pin>`): the right-click menu, over the page (and its sheet), wherever it is drawn.
    PageMenu {
        id: pageMenu
        anchors.fill: parent
        z: 2
        pinId: page.pinId
        report: page.report
        debugLog: page.debugLog
        shownPage: page.active && web.visible
    }

    // A sign-in popup: its own view, drawn over the page until the card closes it (brief "Sites").
    function openSheet(request) {
        closeSheet()
        var s = sheetComp.createObject(page, { pinId: page.pinId, report: page.report, profile: page.profile })
        sheet = s
        request.openIn(s)
    }
    function closeSheet() {
        if (sheet) {
            sheet.destroy()
            sheet = null
        }
    }
    Component {
        id: sheetComp
        PrivateView {
            id: sheetView
            anchors.fill: parent
            z: 1
            onContextMenuRequested: request => pageMenu.show(sheetView, request)
            lifecycleState: recommendedState === WebEngineView.LifecycleState.Active || recentlyAudible
                || (page.active && visible) || page.awake
                ? WebEngineView.LifecycleState.Active : WebEngineView.LifecycleState.Frozen
        }
    }

    // The daemon hears about the page leaving `keep` (the view is gone, its icon stays on disk).
    Component.onDestruction: {
        if (page.report) page.report("webdock.host.unloaded", { pin: page.pinId })
    }
}
