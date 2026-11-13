import QtQuick
import Quickshell

// The desktop's right-click catchers (DeskCatch), one per output. Each is the output's size: measured +3–5 MiB PSS per
// output (live toggle, nested niri, docs/ux/context-menus.md "Budget"), inside BENCH's +6 MiB per output; it commits its
// first frame and none after (0 frames idle).
Variants {
    model: Quickshell.screens
    delegate: DeskCatch {}
}
