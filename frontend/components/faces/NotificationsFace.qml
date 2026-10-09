import QtQuick
import "../../core"

// notifications: unread count from svc.notifications.
FaceBase {
    id: f
    readonly property var d: Store.docs["svc.notifications"] || ({})
    readonly property int unread: d.unread ?? 0
    Watch { doc: "svc.notifications"; active: f.live }

    wantW: row.implicitWidth
    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.gap - 2
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: f.unread > 0 ? Theme.accent : Theme.dim
            font.pixelSize: Theme.fs
            text: f.d.dnd === true ? "⊘" : "◉"
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: f.unread > 0 ? I18n.tr("island.notifications.unread").replace("{n}", f.unread)
                                : I18n.tr("island.notifications.none")
        }
    }
}
