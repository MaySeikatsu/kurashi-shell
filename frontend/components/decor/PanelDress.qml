import QtQuick
import "../../core"
import ".."

// PanelDress (W53.5): what a Block draws round its face, for a surface panel that is not a Block (the Stage's card, the
// quick settings flyout): the look's banded fill (`[decor] fill.bands`, inside the outer grid pixel) and its frame
// (`[slots] frame`, kind card) — a 16-bit RPG window, the PS2's glow line. Lay it over the panel's ground and under its
// content. Nothing is made while the look has neither (rule 4: data only); static.
Item {
    id: pd
    property real radius: Theme.rLg
    property real alpha: 1
    // Draw the bands, the frame, or both (a panel with a band of its own between them lays one under it, one over it).
    property bool bands: true
    property bool frame: true
    readonly property int g: Theme.grid(Screen.height)
    readonly property bool banded: Theme.fillBands > 1
    Loader {
        active: pd.banded && pd.bands
        anchors.fill: parent
        anchors.margins: pd.g
        sourceComponent: Column {
            id: col
            readonly property int n: Theme.bandCount(height, pd.g)
            Repeater {
                model: col.n
                Rectangle {
                    required property int index
                    readonly property int n: col.n
                    readonly property real h0: Math.round(index * parent.height / n)
                    width: parent.width
                    height: Math.round((index + 1) * parent.height / n) - h0
                    antialiasing: pd.g <= 0
                    topLeftRadius: index === 0 ? Math.max(0, pd.radius - pd.g) : 0
                    topRightRadius: index === 0 ? Math.max(0, pd.radius - pd.g) : 0
                    bottomLeftRadius: index === n - 1 ? Math.max(0, pd.radius - pd.g) : 0
                    bottomRightRadius: index === n - 1 ? Math.max(0, pd.radius - pd.g) : 0
                    color: Qt.alpha(Qt.tint(Theme.bandTop, Qt.alpha(Theme.bandBottom, index / (n - 1))), pd.alpha)
                }
            }
        }
    }
    FrameHost {
        visible: pd.frame
        anchors.fill: parent
        radius: pd.radius
        kind: "card"
    }
}
