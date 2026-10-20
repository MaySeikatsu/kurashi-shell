import QtQuick
import "../../core"
import ".."

// bluetooth (K30): a device that just connected. The pill says the daemon's line for it, the device's name and its
// battery when the device reports one (`line`); with no line it says the face's name. The name is elided, so a long
// device name does not stretch the pill. On a side bar the glyph alone; the name is the column's accessible name.
FaceBase {
    id: f
    property string line: ""
    readonly property string full: f.line !== "" ? f.line : I18n.tr("island.face.bluetooth")

    wantW: row.implicitWidth
    wantH: col.implicitHeight
    Row {
        id: row
        visible: !f.vertical
        anchors.centerIn: parent
        spacing: Theme.gap - 2
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "bluetooth_connected"
            glyph: "ᛒ"
            size: Theme.fs + 5
            color: Theme.secondary
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            width: Math.min(implicitWidth, 240)
            elide: Text.ElideRight
            text: f.full
        }
    }
    Column {
        id: col
        visible: f.vertical
        anchors.centerIn: parent
        Accessible.role: Accessible.StaticText
        Accessible.name: f.full
        Icon {
            Accessible.ignored: true
            anchors.horizontalCenter: parent.horizontalCenter
            name: "bluetooth_connected"
            glyph: "ᛒ"
            size: Theme.fs + 3
            color: Theme.secondary
        }
    }
}
