import QtQuick
import "../../core"
import ".."

// notifications: unread count from svc.notifications. On a side bar: the icon over the count (9+ past nine).
// W21: the bell (or the do-not-disturb bell) is an Icon; a new count pops in (OutBack) rather than just changing.
FaceBase {
    id: f
    readonly property var d: Store.docs["svc.notifications"] || ({})
    readonly property int unread: d.unread ?? 0
    readonly property bool dnd: d.dnd === true
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
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: f.dnd ? "notifications_off" : (f.unread > 0 ? "notifications_active" : "notifications")
            glyph: f.dnd ? "⊘" : "◉"
            filled: f.unread > 0
            size: Theme.fs + 4
            color: f.unread > 0 ? Theme.accent : Theme.dim
        }
        Text {
            id: count
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: f.full
            onTextChanged: if (f.animate && f.live && Theme.springOn) pop.restart()
            NumberAnimation {
                id: pop
                target: count
                property: "scale"
                from: 0.6
                to: 1
                duration: Theme.stdMs + 60
                easing.type: Easing.OutBack
                easing.overshoot: Theme.overshoot
            }
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
            name: f.dnd ? "notifications_off" : "notifications"
            glyph: f.dnd ? "⊘" : "◉"
            filled: f.unread > 0
            size: Theme.fs + 3
            color: f.unread > 0 ? Theme.accent : Theme.dim
        }
        Text {
            Accessible.ignored: true
            anchors.horizontalCenter: parent.horizontalCenter
            visible: f.unread > 0
            color: Theme.fg
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: f.unread > 9 ? "9+" : String(f.unread)
        }
    }
}
