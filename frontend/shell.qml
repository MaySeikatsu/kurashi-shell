import QtQuick
import Quickshell
import "surfaces"

// Thin view (CLAUDE.md rule 1): one Bar and one Stage per output; Quickshell.screens follows hotplug.
ShellRoot {
    Variants {
        model: Quickshell.screens
        delegate: Bar {}
    }
    Variants {
        model: Quickshell.screens
        delegate: Stage {}
    }
}
