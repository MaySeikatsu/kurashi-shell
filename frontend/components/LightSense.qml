import QtQuick
import Quickshell
import "../core"

// LightSense (K59, docs/ux/texture.md "Light"): the pointer light's sensor, one per shell window, over the window's whole
// root. It exists only in the pointer mode (no handler otherwise, so nothing listens to the pointer in the other modes).
// It reports the pointer, in output coordinates, to Light, and the window's leave, which starts the glide back to the
// static light. A Wayland client learns the pointer's place only over its own surfaces: the light follows it over the
// shell and no further (Settings says so).
Loader {
    id: sense
    anchors.fill: parent
    active: Theme.lightMode === "pointer"

    readonly property var win: Window.window
    readonly property var qsw: win ? QsWindow.window : null
    readonly property string outName: qsw && qsw.screen ? qsw.screen.name : ""

    sourceComponent: HoverHandler {
        onPointChanged: {
            var o = Light.originOf(sense.qsw)
            Light.moveTo(sense.outName, o.x + point.position.x, o.y + point.position.y)
        }
        onHoveredChanged: if (!hovered) Light.leave(sense.outName)
    }
}
