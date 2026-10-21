import QtQuick
import Quickshell
import Quickshell.Wayland
import "core"

// Kurashi's greetd greeter (W28, docs/ux/greeter.md): a Quickshell config of its own, run by greetd inside a minimal
// compositor (niri or sway; the NixOS module `services.kurashi.greeter`). `core` and `components` are links to
// frontend/, so the greeter draws with the shell's own components and singletons; GreeterTheme fills the documents
// those read, since no kurashid runs before login. One overlay surface per output, keyboard exclusive (DMS
// GreeterSurface); every output shows the same state.
ShellRoot {
    id: root

    Greeter { id: greeter }
    GreeterTheme {
        id: look
        dir: greeter.dir
        user: greeter.user ? greeter.user.name : ""
    }

    Component.onCompleted: {
        // Offline Store: no daemon to dial (no reconnect timer), and the shared views treat the state as current.
        Store.refused = "greeter"
        Store.live = true
    }

    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "kurashi-greeter"
            color: Theme.surface
            GreeterView {
                anchors.fill: parent
                g: greeter
                wallpaper: look.wallpaper
                focus: true
            }
        }
    }
}
