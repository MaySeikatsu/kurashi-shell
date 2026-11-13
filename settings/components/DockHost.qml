import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"

// Settings in a sidebar (W77, K146; docs/ux/settings.md "In a sidebar"): a layer surface exactly over the well of a sidebar
// section `settings`, where `runtime.settings.dock` says it rests — on that output, `x`, `y` px from its top-left corner
// (zones ignored: the shell measures the well where it is on the output, Light.originOf), `width` × `height`, the well's
// `radius`. No backdrop; the keyboard on demand (a click in it gives it the keyboard). The app's one content item
// is put into `slot` (shell.qml); this file knows nothing of pages. Unmapped while the dock is withdrawn (0 frames, Ma).
// The material and light as the sheet's: the shell's Relief registered by this layer's place, its tiles shared.
PanelWindow {
    id: dh
    // runtime.settings.dock: {output, x, y, width, height, radius?}
    property var place: null
    readonly property alias slot: slot
    readonly property real radius: place && place.radius !== undefined ? Number(place.radius) : Theme.rLg
    function screenFor(name) {
        var all = Quickshell.screens
        for (var i = 0; i < all.length; i++)
            if (all[i].name === name) return all[i]
        return null
    }
    readonly property var target: screenFor(place ? String(place.output) : "")
    screen: target
    // (a dock on an output this process does not know — it went — maps nothing)
    visible: !!place && target !== null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // (Top, the sidebar's own layer: mapped after the sidebar's window, it stands over it; under the Stage's cards and the
    // launcher, which are Overlay)
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "kurashi-settings-dock"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    anchors.top: true
    anchors.left: true
    margins.top: place ? place.y : 0
    margins.left: place ? place.x : 0
    implicitWidth: place ? Math.max(1, place.width) : 1
    implicitHeight: place ? Math.max(1, place.height) : 1

    property var tileSheet: dockTiles.item
    Loader {
        id: dockTiles
        active: Theme.texShell && Theme.texTilePx > 0
        sourceComponent: TileSheet {}
    }
    LightSense {}

    // The content fades in once mapped (the well under it is already there, so nothing moves; motion off: at once).
    Glide { id: fade; to: 0 }
    readonly property real shownP: Math.max(0, Math.min(1, fade.value))
    property bool gate: true
    onVisibleChanged: { if (!visible) { gate = true; fade.snap(0) } }
    Connections {
        target: ground.Window.window
        function onFrameSwapped() { if (dh.gate && dh.visible) { dh.gate = false; fade.to = 1 } }
    }

    // The ground (the content rounds its own corners, as on the sheet: no clipping layer under the relief).
    Rectangle {
        id: ground
        anchors.fill: parent
        radius: dh.radius
        color: Theme.surface
    }
    Item {
        id: slot
        anchors.fill: parent
        opacity: dh.shownP
        Accessible.role: Accessible.Pane
        Accessible.name: I18n.tr("settings.ui.title")
    }
}
