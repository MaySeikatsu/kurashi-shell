import QtQuick
import "../core"

// Under Elevation (W57, K78, docs/ux/shadows.md "Elevation"): a card of the look in effect lifted by the elevation in
// effect — the daemon's `elevation.*` tokens through the shell's own Elevation (level 3, a card), so it shows the mode,
// the strength and the direction (away from the light under follow) as they are, and nothing under off (Shōjiki: the
// line beside it says why). Decorative: the rows carry the values, so it is left out of the accessibility tree. Static:
// it changes only with the theme.
Row {
    id: ep
    objectName: "elevation-preview"
    spacing: Theme.pad
    Accessible.ignored: true
    Item {
        width: 160 + 2 * 48
        height: 72 + 2 * 48
        Rectangle {
            anchors.fill: parent
            radius: Theme.rLg
            color: Theme.containerHigh
        }
        Item {
            id: card
            x: 48
            y: 48
            width: 160
            height: 72
            Elevation { anchors.fill: parent; radius: Theme.rLg; level: 3 }
            Rectangle {
                anchors.fill: parent
                radius: Theme.rLg
                color: Theme.panel
                border.width: Theme.outlineW > 0 ? Theme.outlineW : 1
                border.color: Theme.outlineW > 0 ? Theme.line : Theme.containerHigh
            }
        }
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(120, (ep.parent ? ep.parent.width : 420) - 256 - ep.spacing - 8)
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fs - 1
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("settings.elevation." + (Theme.tok("elevation.mode", "off")))
    }
}
