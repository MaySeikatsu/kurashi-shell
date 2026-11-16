import QtQuick
import "../core"

// A sheet as drawn (K165): joined to its bar or band as the bar's cards are (JoinedCard), or the look's card when it
// floats or stands on a bare edge; it slides out of the edge it hangs from (`out` 0..1), or fades and scales when it
// floats; `still` cuts. Fill the sheet's window with it; what it holds goes into its box (the default property), which
// is the sheet inside the fillets.
Item {
    id: sf
    required property var geom         // a SheetGeom
    property real out: 1
    property bool still: false
    property int penSeed: 0x7E83
    default property alias content: box.data
    readonly property alias box: box
    // The box's free side is away from the edge it hangs from (the bottom when it floats).
    readonly property bool freeTop: geom.attached && geom.edge === "bottom"
    clip: geom.attached
    // The slide: the sheet starts behind its edge and comes out of it.
    readonly property real travel: geom.sideways ? geom.winW : geom.winH
    readonly property real shift: geom.attached && !still ? (1 - out) * travel : 0
    Item {
        width: sf.geom.winW
        height: sf.geom.winH
        x: sf.geom.attached && sf.geom.edge === "left" ? -sf.shift : sf.geom.attached && sf.geom.edge === "right" ? sf.shift : 0
        y: sf.geom.attached && sf.geom.edge === "top" ? -sf.shift : sf.geom.attached && sf.geom.edge === "bottom" ? sf.shift : 0
        opacity: sf.geom.attached ? 1 : sf.out
        scale: sf.geom.attached ? 1 : 0.96 + 0.04 * sf.out

        // Joined to its bar or band: one sheet with it (the launcher's and the bar cards' join).
        JoinedCard {
            visible: sf.geom.joins
            x: sf.geom.sideways && sf.geom.edge === "right" ? 0 : (sf.geom.sideways ? -sf.geom.pad : 0)
            y: sf.geom.sideways ? 0 : (sf.geom.edge === "top" ? -sf.geom.pad : 0)
            width: sf.geom.sideways ? sf.geom.winW + sf.geom.pad : sf.geom.winW
            height: sf.geom.sideways ? sf.geom.winH : sf.geom.winH + sf.geom.pad
            pad: sf.geom.pad
            edge: sf.geom.edge
        }
        // Floating, or on a bare edge: the look's card.
        Block {
            visible: !sf.geom.joins
            anchors.fill: parent
            radius: Theme.rLg
            fill: Theme.panel
            flatBorder: Theme.surfaceHair
            penSeed: sf.penSeed
        }
        // The card's box inside the fillets.
        Item {
            id: box
            x: sf.geom.joins && !sf.geom.sideways ? sf.geom.pad : 0
            y: sf.geom.joins && sf.geom.sideways ? sf.geom.pad : 0
            width: sf.geom.sheetW
            height: sf.geom.sheetH
        }
    }
}
