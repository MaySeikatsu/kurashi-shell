import QtQuick
import Quickshell
import "../core"

// Small pill label. Purely presentational. Keycap chrome (K42): an ink outline on the ring colour; the other chromes take
// their outline (K45). Square under square corners (radius.full 0).
Rectangle {
    id: c
    property string text: ""
    property color fg: Theme.dim
    property color bg: Theme.ringW > 0 ? Theme.ring : Theme.surface
    property color edge: Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline
    // K61 (docs/ux/texture.md "Controls"): an opaque pill carries the relief over its fill, under its label (over the
    // label while texture.text is on, as Block), in a window that shares its sheet.
    readonly property var qsw: Window.window ? QsWindow.window : null
    readonly property bool ownRelief: Theme.texControls && c.color.a >= 1 && !!(qsw && qsw.tileSheet)

    implicitWidth: t.implicitWidth + Theme.gap * 1.5 + (Theme.ringW > 0 ? 4 : 0)
    implicitHeight: t.implicitHeight + Theme.xs + (Theme.ringW > 0 ? 2 : 0)
    radius: Theme.rFull
    color: bg
    border.width: Theme.outlineW > 0 ? Math.max(1, Theme.outlineW - 0.5) : 1
    border.color: edge

    Loader {
        active: c.ownRelief && !Theme.texText
        anchors.fill: parent
        anchors.margins: c.border.width
        sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, Math.min(c.radius, c.height / 2) - c.border.width) }
    }
    Text {
        id: t
        anchors.centerIn: parent
        color: Theme.ringW > 0 && c.fg === Theme.dim ? Theme.line : c.fg
        font.pixelSize: Theme.fsCaption
        font.weight: Theme.wMedium
        font.family: Theme.fam(text, Theme.families)
        text: c.text
    }
    Loader {
        active: c.ownRelief && Theme.texText
        anchors.fill: parent
        anchors.margins: c.border.width
        sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, Math.min(c.radius, c.height / 2) - c.border.width) }
    }
}
