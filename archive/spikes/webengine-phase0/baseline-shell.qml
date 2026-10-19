import QtQuick
import Quickshell
import Quickshell.Wayland
ShellRoot {
    PanelWindow {
        anchors { left: true; top: true; bottom: true }
        implicitWidth: 480
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        color: "#2b3a55"
        Text { anchors.centerIn: parent; text: "baseline"; color: "white"; font.pixelSize: 20 }
        Component.onCompleted: console.log("SPIKE LOAD 2")
    }
}
