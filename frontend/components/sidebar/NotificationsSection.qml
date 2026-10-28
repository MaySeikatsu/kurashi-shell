import QtQuick
import Quickshell
import "../../core"
import ".."
import "../expanded"
import "../island"

// The right sidebar's `notifications` (docs/ux/sidebar.md; ii `sidebarRight/CenterWidgetGroup.qml`): the title with Clear
// all, do not disturb (the daemon's state; off: a one-hour choice), then every notification, newest first, as the shared
// NotificationCard. The section takes the column's free height and the list scrolls inside it, so the column never
// overflows the output. While the session is locked the content is hidden and the section says so (as the island view).
// The list is the daemon's; this only orders it. Watches svc.notifications and runtime.lock while the sidebar is open.
Item {
    id: ns
    // The least height that keeps two cards in view; the column gives it the rest of the output.
    readonly property int minHeight: head.height + Theme.gap + 180
    implicitHeight: minHeight

    Watch { doc: "svc.notifications" }
    Watch { doc: "runtime.lock" }
    readonly property var n: Store.docs["svc.notifications"] || ({})
    readonly property var items: (n.items || []).slice().sort(function (a, b) { return (b.time ?? 0) - (a.time ?? 0) })
    readonly property bool locked: (Store.docs["runtime.lock"] || ({})).locked === true
    readonly property bool dnd: n.dnd === true
    readonly property var dndUntil: n.dnd_until
    property string errText: ""
    Refusal { id: refusal }
    function act(action, args) {
        ns.errText = ""
        Store.act(action, args, function (done, err) { if (err) ns.errText = refusal.text(err, "island.notifications.failed") })
    }

    Column {
        id: head
        width: ns.width
        spacing: Theme.gap
        Row {
            width: ns.width
            spacing: Theme.gap
            Text {
                width: ns.width - clearAll.width - Theme.gap
                height: clearAll.height
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("notifications.center.title")
                    + (ns.items.length > 0 && !ns.locked ? "  " + ns.items.length : "")
            }
            KeyButton {
                id: clearAll
                side: 28
                icon: "clear_all"
                iconSize: Theme.fs + 4
                label: I18n.tr("island.notifications.clear")
                enabled: ns.items.length > 0 && !ns.locked
                onClicked: ns.act("notify.dismiss", {})
            }
        }
        // Do not disturb, on a plate: tonal while it is on.
        Rectangle {
            width: ns.width
            height: dndRow.height + 2 * Theme.gap
            // (concentric with the column, as the section plates: I269)
            radius: QsWindow.window && QsWindow.window.sectionR !== undefined ? QsWindow.window.sectionR : Theme.rLg
            color: ns.dnd ? Theme.selected : Theme.containerHigh
            Row {
                id: dndRow
                x: Theme.pad
                y: Theme.gap
                width: parent.width - 2 * Theme.pad
                spacing: Theme.gap
                ToggleSwitch {
                    id: dndSwitch
                    anchors.verticalCenter: parent.verticalCenter
                    checked: ns.dnd
                    label: I18n.tr("island.notifications.dnd")
                    onToggled: on => ns.act("notify.dnd", {on: on})
                }
                Column {
                    width: dndRow.width - dndSwitch.width - (hourBtn.visible ? hourBtn.width + Theme.gap : 0) - Theme.gap
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("island.notifications.dnd")
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                        text: !ns.dnd ? I18n.tr("island.notifications.dnd.off")
                            : (ns.dndUntil !== undefined && ns.dndUntil !== null)
                                ? I18n.tr("island.notifications.dnd.until").replace("{t}", Qt.formatTime(new Date(ns.dndUntil), "hh:mm"))
                            : I18n.tr("island.notifications.dnd.on")
                    }
                }
                KeyButton {
                    id: hourBtn
                    anchors.verticalCenter: parent.verticalCenter
                    side: 28
                    icon: "timer"
                    iconSize: Theme.fs + 4
                    visible: !ns.dnd
                    label: I18n.tr("island.notifications.dnd.hour")
                    onClicked: ns.act("notify.dnd", {on: true, until: Date.now() + 3600000})
                }
            }
        }
        Text {
            visible: ns.errText !== ""
            width: ns.width
            wrapMode: Text.WordWrap
            color: Theme.error
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: ns.errText
        }
    }

    // The list, scrolled inside the section.
    ListView {
        id: list
        y: head.height + Theme.gap
        width: ns.width
        height: Math.max(0, ns.height - y)
        clip: true
        spacing: Theme.gap
        boundsBehavior: Flickable.StopAtBounds
        model: ns.locked ? [] : ns.items
        // Cards keep their focus across list updates; Tab walks the cards' own controls.
        keyNavigationEnabled: false
        delegate: NotificationCard {
            required property var modelData
            width: list.width
            item: modelData
            onDismissed: ns.act("notify.dismiss", {id: modelData.id})
            onInvoked: key => ns.act("notify.invoke", {id: modelData.id, key: key})
        }
    }
    Text {
        visible: ns.locked || ns.items.length === 0
        y: list.y + Theme.pad
        width: ns.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: ns.locked ? I18n.tr("island.notifications.locked") : I18n.tr("notifications.center.empty")
    }
}
