import QtQuick
import Quickshell
import QtWebEngine
import "core"

// A WebEngineView with the web dock's privacy settings (docs/ux/webdock.md "Privacy", K38) and the requests it
// answers itself: a permission is refused and reported, a popup with an opener (a dialog) is handed to the card as a
// sheet, a link for a new tab or window loads in this view (`new_tabs = dock`, K40; Back returns) or goes to the
// browser (`new_tabs = browser`, the daemon runs `open_external`), a stopped renderer and the audible state are
// reported. Reports carry `pinId`; `report(action, args)` sends them (the host's Store.act).
WebEngineView {
    id: view

    property string pinId: ""
    property var report: null
    // new_tabs (K40): true loads a link for a new tab or window in this view; false reports it for the browser.
    property bool newTabsInDock: true
    // A popup with an opener (a sign-in window): the owner opens it as a sheet with `request.openIn(view)`.
    signal sheetRequested(var request)
    readonly property bool debugLog: Quickshell.env("KURASHI_WEBDOCK_DEBUG") === "1"

    backgroundColor: Theme.surface
    // Errors are drawn by the card, not by the engine's own error page (which would load its own resources).
    settings.errorPageEnabled: false
    settings.hyperlinkAuditingEnabled: false
    settings.dnsPrefetchEnabled: false
    settings.webRTCPublicInterfacesOnly: true
    settings.javascriptCanAccessClipboard: false
    settings.localContentCanAccessRemoteUrls: false
    // The engine fetches no page icon (favicon.ico, touch icons): the net log test found the favicon.ico request
    // of a page the fixture did not make. Letter tiles stand in for the icons (docs/ux/webdock.md "Privacy").
    settings.autoLoadIconsForPage: false
    settings.touchIconsEnabled: false

    function send(action, args) {
        if (report) report(action, args)
    }

    // The permission names the daemon's `webdock.host.blocked` takes (PROTOCOL: webdock.blocked.<permission>).
    function permissionNames(kind) {
        switch (kind) {
        case WebEnginePermission.PermissionType.MediaVideoCapture: return ["camera"]
        case WebEnginePermission.PermissionType.MediaAudioCapture: return ["microphone"]
        case WebEnginePermission.PermissionType.MediaAudioVideoCapture: return ["camera", "microphone"]
        case WebEnginePermission.PermissionType.Geolocation: return ["location"]
        case WebEnginePermission.PermissionType.Notifications: return ["notifications"]
        case WebEnginePermission.PermissionType.DesktopVideoCapture:
        case WebEnginePermission.PermissionType.DesktopAudioVideoCapture: return ["screen"]
        case WebEnginePermission.PermissionType.ClipboardReadWrite: return ["clipboard"]
        default: return ["other"]
        }
    }

    onPermissionRequested: permission => {
        // Never stored (the profile asks every time) and never granted in v1 (brief "Sites").
        permission.deny()
        var names = permissionNames(permission.permissionType)
        for (var i = 0; i < names.length; i++)
            send("webdock.host.blocked", { pin: pinId, permission: names[i] })
    }

    // Qt 6.11 has one request signal for every destination (`newWindowRequested`, with `destination`). Declined by not
    // calling `openIn`, so the engine creates no view: the link loads here, and the history keeps the page it came from.
    onNewWindowRequested: request => {
        if (request.destination === WebEngineView.NewViewInDialog) {
            sheetRequested(request)
        } else if (newTabsInDock) {
            if (String(request.requestedUrl) !== "") view.url = request.requestedUrl
        } else {
            send("webdock.host.new_window", { pin: pinId, url: String(request.requestedUrl) })
        }
    }

    // The address the view is at: the test reads it to see a link or Back take effect (KURASHI_WEBDOCK_DEBUG=1 only).
    onUrlChanged: if (debugLog) console.log("webdock-debug url", pinId, String(url))

    onRenderProcessTerminated: (status, code) => send("webdock.host.crashed", { pin: pinId })

    onRecentlyAudibleChanged: send("webdock.host.audible", { pin: pinId, on: recentlyAudible })

    // The page's console goes to the host's log only when the test asks for it (KURASHI_WEBDOCK_DEBUG=1):
    // the typed text of a fixture page is how the B27 keyboard test reads what arrived.
    onJavaScriptConsoleMessage: (level, message, line, source) => {
        if (debugLog) console.log("webdock-debug", pinId, message)
    }
}
