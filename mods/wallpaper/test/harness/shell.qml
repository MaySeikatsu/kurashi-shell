import QtQuick
import Quickshell
import Quickshell.Wayland
// The core is imported by file URL: the script writes this file with @ROOT@ filled in, because a
// relative import from a root outside frontend/ does not resolve here (the mod components' own relative
// imports do).
import "file://@ROOT@/frontend/core"

// Scratch host for one mod component, for the picker test (mods/wallpaper/test/picker.sh) only. It
// stands in for the Stage / quick-settings hosts until W11-mod-qml loads mod components in the shell.
// It subscribes the same theme and strings the shell does, and shows the file named by WP_COMPONENT.
ShellRoot {
    Watch { doc: "theme" }
    Watch { doc: "i18n" }

    PanelWindow {
        id: win
        anchors.top: true
        anchors.left: true
        margins.top: 40
        margins.left: 40
        implicitWidth: host.item ? host.item.implicitWidth + 2 * Theme.pad : 760
        implicitHeight: host.item ? host.item.implicitHeight + 2 * Theme.pad : 520
        color: Theme.surface

        Loader {
            id: host
            anchors.fill: parent
            anchors.margins: Theme.pad
            source: "file://" + Quickshell.env("WP_COMPONENT")
        }
    }
}
