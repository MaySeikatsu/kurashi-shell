import QtQuick
import Quickshell
import "../../core"

// Which output a sidebar that `runtime.ui.sidebar` names is open on (the side and the edge sidebars share it): the output
// the daemon names (`sidebar_output`), else the focused one, latched while it is open (the daemon may name another
// while it is open: then that one).
QtObject {
    id: oo
    property string side: ""
    // shell.qml's focused output, read when the sidebar opens without a named output.
    property var focusedScreen: null
    readonly property var ui: Store.docs["runtime.ui"] || ({})
    readonly property bool toggled: ui.sidebar === side
    readonly property string wantOutput: toggled && typeof ui.sidebar_output === "string" ? ui.sidebar_output : ""
    property string toggledOn: ""
    function screenNamed(n) {
        var s = Quickshell.screens
        for (var i = 0; i < s.length; i++) if (s[i].name === n) return s[i]
        return null
    }
    function pickName() {
        var s = wantOutput !== "" ? screenNamed(wantOutput) : null
        if (s === null) s = focusedScreen || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
        return s ? s.name : ""
    }
    onToggledChanged: toggledOn = toggled ? pickName() : ""
    onWantOutputChanged: if (toggled) toggledOn = pickName()
    Component.onCompleted: if (toggled) toggledOn = pickName()
}
