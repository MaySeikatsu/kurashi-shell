import QtQuick
import Quickshell

ShellRoot {
    // One bar per output; Quickshell.screens updates on hotplug.
    Variants {
        model: Quickshell.screens
        delegate: Bar {}
    }
}
