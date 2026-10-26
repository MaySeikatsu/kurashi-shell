import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"

// The edge strips of one output (EdgeStrips, K71): for each edge, a 4 px window with a 2 px input zone at the very edge,
// only while something on that edge reveals on hover. It reports the pointer's place along the edge and nothing else;
// over a bar's or the frame's outer pixels too (Fitts: the edge is the target). Click-through elsewhere, no keyboard.
Scope {
    id: host
    required property var modelData

    component Strip: Scope {
        id: st
        required property string edge
        readonly property bool side: edge === "left" || edge === "right"
        LazyLoader {
            active: EdgeStrips.wanted(host.modelData ? host.modelData.name : "", st.edge)
            PanelWindow {
                id: win
                screen: host.modelData
                implicitWidth: st.side ? 4 : 0
                implicitHeight: st.side ? 0 : 4
                anchors.top: st.edge !== "bottom"
                anchors.bottom: st.edge !== "top"
                anchors.left: st.edge !== "right"
                anchors.right: st.edge !== "left"
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "kurashi-edge"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: Region { item: zone }
                Item {
                    id: zone
                    x: st.edge === "right" ? parent.width - 2 : 0
                    y: st.edge === "bottom" ? parent.height - 2 : 0
                    width: st.side ? 2 : parent.width
                    height: st.side ? parent.height : 2
                    HoverHandler {
                        id: hov
                        onPointChanged: if (hovered) EdgeStrips.setPos(host.modelData.name, st.edge,
                                                                       st.side ? point.position.y : point.position.x)
                        onHoveredChanged: if (!hovered) EdgeStrips.setPos(host.modelData.name, st.edge, -1)
                    }
                }
                Component.onDestruction: EdgeStrips.setPos(host.modelData ? host.modelData.name : "", st.edge, -1)
            }
        }
    }
    Strip { edge: "top" }
    Strip { edge: "bottom" }
    Strip { edge: "left" }
    Strip { edge: "right" }
}
