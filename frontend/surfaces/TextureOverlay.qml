import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"

// The everything scope (K59, docs/ux/texture.md): one overlay per output that draws the material's relief over the whole
// output, apps included. It is a layer surface on the Overlay layer with an empty input region (a click passes through
// to whatever lies under it), exclusion ignored and no keyboard focus. The shell's own surfaces draw no relief meanwhile
// (texture.shell is off in this scope), so nothing is shaded twice. Settings says what it costs: fullscreen windows lose
// direct scanout, and the overlay shows in screenshots and screencasts.
PanelWindow {
    id: overlay
    required property var modelData

    screen: modelData
    // Only while the everything scope is on: no layer surface at all otherwise (Ma).
    visible: Theme.texOverlay
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "kurashi-texture"
    color: "transparent"
    mask: Region {}

    // The sheet is registered to this output (anchored to all four edges, so its origin is the output's own).
    property var tileSheet: tilesLoader.item
    Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
    Relief { anchors.fill: parent }
}
