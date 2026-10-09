import QtQuick
import "../../core"
import ".."

// The expanded view of the notifications face (K24): the newest five of svc.notifications as cards
// (dismiss, invoke), and the way to the whole list. Watches svc.notifications only while it is on
// screen (Ma). The list is the daemon's; this view only picks its head.
Column {
    id: view
    width: parent.width
    spacing: Theme.gap

    Watch { doc: "svc.notifications" }
    readonly property var items: (Store.docs["svc.notifications"] || ({})).items || []
    readonly property var newest: items.slice(0, 5)

    Text {
        width: view.width
        color: Theme.fg
        font.pixelSize: Theme.fsTitle
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("notifications.center.title")
    }
    Text {
        visible: view.newest.length === 0
        width: view.width
        color: Theme.dim
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("notifications.center.empty")
    }
    Repeater {
        model: view.newest
        delegate: NotificationCard {
            required property var modelData
            width: view.width
            item: modelData
            onDismissed: Store.act("notify.dismiss", {id: modelData.id})
            onInvoked: key => Store.act("notify.invoke", {id: modelData.id, key: key})
        }
    }
    Button {
        label: I18n.tr("island.notifications.all")
        onClicked: Store.act("notifications.center")
    }
}
