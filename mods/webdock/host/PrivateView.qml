import QtQuick
import Quickshell
import QtWebEngine
import "core"

// A WebEngineView with the web dock's privacy settings (docs/ux/webdock.md "Privacy", K38) and the requests it
// answers itself: a permission is refused and reported, a new tab or window goes to the browser (the daemon runs
// `open_external`), a popup with an opener is handed to the card as a sheet, a stopped renderer and the audible
// state are reported. Reports carry `pinId`; `report(action, args)` sends them (the host's Store.act).
WebEngineView {
    id: view

    property string pinId: ""
    property var report: null
    // A popup with an opener (a sign-in window): the owner opens it as a sheet with `request.openIn(view)`.
    signal sheetRequested(var request)

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

    onNewWindowRequested: request => {
        if (request.destination === WebEngineView.NewViewInDialog) {
            sheetRequested(request)
        } else {
            send("webdock.host.new_window", { pin: pinId, url: String(request.requestedUrl) })
        }
    }

    onRenderProcessTerminated: (status, code) => send("webdock.host.crashed", { pin: pinId })

    onRecentlyAudibleChanged: send("webdock.host.audible", { pin: pinId, on: recentlyAudible })

    // The page's console goes to the host's log only when the test asks for it (KURASHI_WEBDOCK_DEBUG=1):
    // the typed text of a fixture page is how the B27 keyboard test reads what arrived.
    onJavaScriptConsoleMessage: (level, message, line, source) => {
        if (Quickshell.env("KURASHI_WEBDOCK_DEBUG") === "1")
            console.log("webdock-debug", pinId, message)
    }
}
