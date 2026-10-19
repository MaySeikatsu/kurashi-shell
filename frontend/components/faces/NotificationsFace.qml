import QtQuick
import "../../core"

// notifications: unread count from svc.notifications. On a side bar: the glyph over the count (9+ past nine).
FaceBase {
    id: f
    readonly property var d: Store.docs["svc.notifications"] || ({})
    readonly property int unread: d.unread ?? 0
    readonly property string full: f.unread > 0 ? I18n.tr("island.notifications.unread").replace("{n}", f.unread)
        : I18n.tr("island.notifications.none")
    Watch { doc: "svc.notifications"; active: f.live }

    wantW: row.implicitWidth
    wantH: col.implicitHeight
    Row {
        id: row
        visible: !f.vertical
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
            text: f.full
        }
    }
    Column {
        id: col
        visible: f.vertical
        anchors.centerIn: parent
        Accessible.role: Accessible.StaticText
        Accessible.name: f.full
        Text {
            Accessible.ignored: true
            color: f.unread > 0 ? Theme.accent : Theme.dim
            font.pixelSize: Theme.fs
            text: f.d.dnd === true ? "⊘" : "◉"
        }
        Text {
            Accessible.ignored: true
            visible: f.unread > 0
            color: Theme.fg
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: f.unread > 9 ? "9+" : String(f.unread)
        }
    }
}
