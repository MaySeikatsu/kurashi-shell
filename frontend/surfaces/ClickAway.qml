import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"

// A click elsewhere closes what a click opened (I279: no Close buttons; Esc does the same). While a Stage card, the
// launcher, the notification centre or a tray menu is open, one transparent window per output over the usable area takes
// a press and runs `ui.close`. A layer surface sees no click outside itself and niri gives layer surfaces no focus grab,
// so the catcher is the click (as the toggled sidebar's, I152). It sits on the top layer, under the popups (overlay)
// and over the apps; placed in the usable area (exclusive zones respected), it leaves the bars and the frame their
// clicks — a bar widget still opens its own card. No window while nothing is open (Ma); none under a polkit dialog,
// which keeps the panels shut itself.
Scope {
    id: ca
    required property var modelData

    Watch { doc: "runtime.ui" }
    readonly property var ui: Store.docs["runtime.ui"] || ({})
    readonly property bool open: ui.polkit !== true
        && ((ui.panel || "") !== "" || ui.launcher === true || (ui.tray || "") !== "")

    LazyLoader {
        active: ca.open
        PanelWindow {
            screen: ca.modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "kurashi-clickaway"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: Store.act("ui.close")
            }
        }
    }
}
