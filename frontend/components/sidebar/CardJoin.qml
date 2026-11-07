import QtQuick
import "."

// What a card standing on a bar or band asks of what lies under it, while the look is translucent (I435, docs/ux/layout.md
// "Draw modes"). The bar's and the band's rule would show through the card as a line along the connecting edge, and the
// sheet's shadow as a dark neck: the rule is left out over the card's span (SidebarGeom.openings, as for a sidebar's column)
// and the shadow is cut under its box (SidebarGeom.cards). An opaque card simply covers them: nothing is published then.
//   spans  [{ edge, from, to }] along each edge it meets, in output px
//   box    the card's box in output px
QtObject {
    id: cj
    property string output: ""
    property string side: ""
    property bool on: false
    property var spans: []
    property rect box: Qt.rect(0, 0, 0, 0)
    property string held: ""
    readonly property string key: on && output !== ""
        ? JSON.stringify([output, spans, box.x, box.y, box.width, box.height]) : ""
    function withdraw() {
        if (held === "") return
        SidebarGeom.clear(held, side)
        SidebarGeom.setCard(held, side, null)
        held = ""
    }
    onKeyChanged: {
        withdraw()
        if (key === "") return
        held = output
        for (var i = 0; i < spans.length; i++) SidebarGeom.set(output, side, spans[i].edge, spans[i].from, spans[i].to)
        SidebarGeom.setCard(output, side, box)
    }
    Component.onDestruction: withdraw()
}
