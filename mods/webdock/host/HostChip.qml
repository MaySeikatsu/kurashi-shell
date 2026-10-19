import QtQuick
import "core"

// A permission chip of the card header ("Blocked: camera", docs/ux/webdock.md "Sites"). Presentational only.
Rectangle {
    id: c

    property string text: ""

    implicitWidth: t.implicitWidth + Theme.gap * 1.5
    implicitHeight: t.implicitHeight + Theme.xs
    radius: Theme.rFull
    color: Theme.surface
    border.width: 1
    border.color: Theme.error

    Text {
        id: t
        anchors.centerIn: parent
        text: c.text
        color: Theme.error
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
    }
}
