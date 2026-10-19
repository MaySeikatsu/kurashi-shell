//@ pragma Env LD_PRELOAD =
//@ pragma ShareOpenGLContexts
import QtQuick
import Quickshell
import Quickshell.Wayland
import QtWebEngine

ShellRoot {
    PanelWindow {
        id: win
        anchors { left: true; top: true; bottom: true }
        implicitWidth: 480
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        color: "#202020"

        WebEngineProfile {
            id: prof
            storageName: "spike-pin-a"
            offTheRecord: false
            persistentStoragePath: Quickshell.env("SPIKE_STORE")
        }
        WebEngineView {
            id: view
            anchors.fill: parent
            profile: prof
            url: Quickshell.env("SPIKE_URL")
            focus: true
            onTitleChanged: console.log("SPIKE TITLE", title)
            onLoadingChanged: req => console.log("SPIKE LOAD", req.status, req.errorString)
            onJavaScriptConsoleMessage: (level, message, line, source) => console.log("SPIKE JS", message)
            onRenderProcessTerminated: (status, code) => console.log("SPIKE RENDER-DIED", status, code)
            Component.onCompleted: { forceActiveFocus(); console.log("SPIKE storage", prof.persistentStoragePath, prof.offTheRecord) }
        }
    }
}
