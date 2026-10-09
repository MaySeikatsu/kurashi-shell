import QtQuick
import "../../core"

// bluetooth (K30): a device that just connected. The pill says the daemon's line for it, the device's name and its
// battery when the device reports one (`line`); with no line it says the face's name. The name is elided, so a long
// device name does not stretch the pill.
FaceBase {
    id: f
    property string line: ""

    wantW: row.implicitWidth
    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.gap - 2
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.accent
            font.pixelSize: Theme.fs + 2
            text: "ᛒ"
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            width: Math.min(implicitWidth, 240)
            elide: Text.ElideRight
            text: f.line !== "" ? f.line : I18n.tr("island.face.bluetooth")
        }
    }
}
