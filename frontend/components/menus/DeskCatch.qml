import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../core"

// The desktop's right click (W82, docs/ux/context-menus.md): the wallpaper is another program's surface (awww, swww,
// swaybg — they take no input), so nothing of the shell's is under the pointer there. One empty window per output on the
// background layer — over the wallpaper's, under the desktop widgets (bottom layer) and every window — takes the right
// click and opens the desktop's menu at the pointer (MenuAt). It draws nothing after its first frame and watches nothing
// (Ma); a left or middle click does nothing.
PanelWindow {
    id: dc
    required property var modelData
    screen: modelData
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "kurashi-desk-catch"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (point) => MenuAt.open("desktop:" + (dc.screen ? dc.screen.name : ""), dc.screen ? dc.screen.name : "",
                                         point.position.x, point.position.y)
    }
}
