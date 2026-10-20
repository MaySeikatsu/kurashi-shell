import QtQuick
import "../core"

// Small pill label. Purely presentational. Keycap chrome (K42): an ink outline on the ring colour; the other chromes take
// their outline (K45). Square under square corners (radius.full 0).
Rectangle {
    id: c
    property string text: ""
    property color fg: Theme.dim
    property color bg: Theme.ringW > 0 ? Theme.ring : Theme.surface
    property color edge: Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline

    implicitWidth: t.implicitWidth + Theme.gap * 1.5 + (Theme.ringW > 0 ? 4 : 0)
    implicitHeight: t.implicitHeight + Theme.xs + (Theme.ringW > 0 ? 2 : 0)
    radius: Theme.rFull
    color: bg
    border.width: Theme.outlineW > 0 ? Math.max(1, Theme.outlineW - 0.5) : 1
    border.color: edge

    Text {
        id: t
        anchors.centerIn: parent
        color: Theme.ringW > 0 && c.fg === Theme.dim ? Theme.line : c.fg
        font.pixelSize: Theme.fsCaption
        font.weight: Theme.wMedium
        font.family: Theme.fam(text, Theme.families)
        text: c.text
    }
}
