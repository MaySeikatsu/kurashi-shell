import QtQuick
import "../../core"
import ".."

// The expanded view of the notifications face (K24; island brief 5): the list grouped by app (the group of the newest
// note first; ongoing notes first inside a group), each note with its actions and its dismiss, Clear all, and do not
// disturb with its end ("until 14:30" when timed, otherwise "until you turn it off"). While the session is locked the
// content is hidden and the view says so. Watches svc.notifications and runtime.lock only while on screen (Ma). The
// list is the daemon's; this view only groups its head.
Column {
    id: view
    width: parent.width
    spacing: Theme.gap

    Watch { doc: "svc.notifications" }
    Watch { doc: "runtime.lock" }
    readonly property var n: Store.docs["svc.notifications"] || ({})
    readonly property var items: n.items || []
    readonly property bool locked: (Store.docs["runtime.lock"] || ({})).locked === true
    readonly property bool dnd: n.dnd === true
    // ms since the epoch; present only while timed do-not-disturb is on.
    readonly property var dndUntil: n.dnd_until
    readonly property string dndText: !dnd ? I18n.tr("island.notifications.dnd.off")
        : (dndUntil !== undefined && dndUntil !== null)
          ? I18n.tr("island.notifications.dnd.until").replace("{t}", Qt.formatTime(new Date(dndUntil), "hh:mm"))
          : I18n.tr("island.notifications.dnd.on")
    // The list's head, at most `maxCards` notes, grouped. Groups keep the order of their newest note; inside a group the
    // ongoing (resident) notes come first. The rest stays one click away in the notification center.
    readonly property int maxCards: 8
    readonly property var groups: {
        var sorted = items.slice().sort(function (a, b) { return (b.time ?? 0) - (a.time ?? 0) })
        var out = [], at = ({}), count = 0
        for (var i = 0; i < sorted.length && count < maxCards; i++) {
            var app = String(sorted[i].app_name ?? "")
            if (at[app] === undefined) { at[app] = out.length; out.push({app: app, items: []}) }
            out[at[app]].items.push(sorted[i])
            count++
        }
        for (var g = 0; g < out.length; g++)
            out[g].items.sort(function (a, b) { return (b.resident === true ? 1 : 0) - (a.resident === true ? 1 : 0) })
        return out
    }
    property string errText: ""
    Refusal { id: refusal }

    function act(action, args, msg) {
        view.errText = ""
        Store.act(action, args, function (done, err) { if (err) view.errText = refusal.text(err, msg) })
    }
    function setDnd(on) { act("notify.dnd", {on: on}, "island.notifications.failed") }
    // The quick choice: one hour, after which the daemon turns do-not-disturb off by itself.
    function setDndHour() { act("notify.dnd", {on: true, until: Date.now() + 3600000}, "island.notifications.failed") }

    Row {
        width: view.width
        spacing: Theme.gap
        Text {
            width: view.width - clearAll.width - Theme.gap
            height: clearAll.height
            verticalAlignment: Text.AlignVCenter
            color: Theme.fg
            font.pixelSize: Theme.fsTitle
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("notifications.center.title")
        }
        Button {
            id: clearAll
            label: I18n.tr("island.notifications.clear")
            enabled: view.items.length > 0
            onClicked: view.act("notify.dismiss", {}, "island.notifications.failed")
        }
    }
    StaleNote { face: "notifications" }

    // Do not disturb: the switch is the state (the daemon's), the caption says until when. Off, a one-hour choice.
    Row {
        id: dndRow
        width: view.width
        spacing: Theme.gap
        ToggleSwitch {
            id: dndSwitch
            anchors.verticalCenter: parent.verticalCenter
            checked: view.dnd
            label: I18n.tr("island.notifications.dnd")
            onToggled: on => view.setDnd(on)
        }
        Column {
            width: view.width - dndSwitch.width - (hourBtn.visible ? hourBtn.width + Theme.gap : 0) - Theme.gap
            spacing: 0
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
                text: view.dndText
            }
        }
        Button {
            id: hourBtn
            anchors.verticalCenter: parent.verticalCenter
            visible: !view.dnd
            label: I18n.tr("island.notifications.dnd.hour")
            onClicked: view.setDndHour()
        }
    }

    // K28: a mod's header row (a focus or DND schedule); nothing when no mod contributes.
    SlotHost { slot: "notifications.expanded.header"; width: view.width }

    Text {
        visible: view.locked
        width: view.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.notifications.locked")
    }
    Text {
        visible: !view.locked && view.items.length === 0
        width: view.width
        color: Theme.dim
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("notifications.center.empty")
    }
    Repeater {
        model: view.locked ? [] : view.groups
        delegate: Column {
            id: group
            required property var modelData
            width: view.width
            spacing: Theme.xs
            Text {
                width: parent.width
                elide: Text.ElideRight
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: group.modelData.app
            }
            Repeater {
                model: group.modelData.items
                delegate: NotificationCard {
                    required property var modelData
                    width: group.width
                    item: modelData
                    onDismissed: view.act("notify.dismiss", {id: modelData.id}, "island.notifications.failed")
                    onInvoked: key => view.act("notify.invoke", {id: modelData.id, key: key}, "island.notifications.failed")
                }
            }
        }
    }
    Text {
        visible: view.errText !== ""
        width: view.width
        wrapMode: Text.WordWrap
        color: Theme.error
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: view.errText
    }
    Button {
        label: I18n.tr("island.notifications.all")
        onClicked: Store.act("notifications.center")
    }
}
