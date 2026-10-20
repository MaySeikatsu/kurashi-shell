import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../core"

// Rounded screen corners (K47 (6), `theme.shape.screen_corners`): four concave quarter-circle fillets in black — the
// panel's own edge — at the corners of one output, while the radius is > 0 (shellseikatsu `Widgets/ScreenCorners.qml`,
// Caelestia's rounded border). Click-through (`mask: Region {}`), no keyboard, top layer, ignoring exclusive zones so
// they sit on the panel's corners. Unlike shellseikatsu's one full-screen surface, each corner is its own r × r surface:
// four tiny buffers instead of a transparent full-output one. Static: drawn once (a Shape, no Canvas, no animation), 0
// frames idle; no surface at all while the radius is 0.
Scope {
    id: sc
    required property var modelData

    BarConfig { id: cfg; screen: sc.modelData }
    readonly property int radius: {
        var r = cfg.valueOf("theme.shape.screen_corners", 0)
        return typeof r === "number" && r > 0 ? Math.round(r) : 0
    }

    // One fillet: black from the corner to the arc, drawn for the top-left corner and turned for the others.
    component Corner: PanelWindow {
        id: corner
        property int turn: 0
        screen: sc.modelData
        implicitWidth: sc.radius
        implicitHeight: sc.radius
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "kurashi-corners"
        color: "transparent"
        mask: Region {}
        Shape {
            anchors.fill: parent
            rotation: corner.turn
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "black"
                strokeWidth: -1
                startX: 0; startY: 0
                PathLine { x: sc.radius; y: 0 }
                PathArc { x: 0; y: sc.radius; radiusX: sc.radius; radiusY: sc.radius; direction: PathArc.Counterclockwise }
                PathLine { x: 0; y: 0 }
            }
        }
    }

    LazyLoader {
        active: sc.radius > 0
        Scope {
            Corner { anchors { top: true; left: true } turn: 0 }
            Corner { anchors { top: true; right: true } turn: 90 }
            Corner { anchors { bottom: true; right: true } turn: 180 }
            Corner { anchors { bottom: true; left: true } turn: 270 }
        }
    }
}
