import QtQuick
import QtWebEngine

// One pin's page in the card's body (MODS.md "Web dock": one view per pin in `keep`). It exists while its pin is in
// `keep` (the Repeater creates it when the pin is first shown and destroys it when the pin leaves `keep`, which
// reports `unloaded`). The card draws only the shown page; the others are hidden and Frozen unless audible.
Item {
    id: page

    property string pinId: ""
    property string target: ""
    property var profile: null
    property var report: null
    // The profile's view: "mobile" or "desktop". A change reloads the page (the user agent is sent with a request).
    property string mode: ""
    property bool active: false

    // What the card draws: the first paint (the skeleton goes), a failed load (code and text), a popup sheet.
    property bool painted: false
    property var loadError: null
    property var sheet: null
    readonly property var engine: web

    anchors.fill: parent
    // Only the shown pin's page is drawn — its sign-in sheet included (a sheet stayed over the next pin otherwise).
    visible: active

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
        report: page.report
        profile: page.profile
        url: page.target
        visible: page.active
        focus: page.active
        // Hidden pages are Frozen (no timers, no painting) unless they play audio (brief "Fit and constraints").
        lifecycleState: (page.active || web.recentlyAudible) ? WebEngineView.LifecycleState.Active
            : WebEngineView.LifecycleState.Frozen

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
        onSheetRequested: request => page.openSheet(request)
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
            anchors.fill: parent
            z: 1
            lifecycleState: (page.active || recentlyAudible) ? WebEngineView.LifecycleState.Active
                : WebEngineView.LifecycleState.Frozen
        }
    }

    // The daemon hears about the page leaving `keep` (the view is gone, its icon stays on disk).
    Component.onDestruction: {
        if (page.report) page.report("webdock.host.unloaded", { pin: page.pinId })
    }
}
