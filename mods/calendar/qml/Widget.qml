import QtQuick
import qs.core
import qs.components
import "Calendar.js" as C

// Bar widget of the calendar mod (docs/ux/calendar.md "Views"): an event icon and "Standup · 12 min" while the next
// timed event starts within the hour, "Standup · now" while it runs; nothing at all otherwise (it takes no room). On a
// side bar the icon and the minutes stack. A click (Return, Enter, Space) opens the island's card (the clock with the
// day's agenda). Ma: no ticking while there is nothing to show; one timer is armed for the moment an event comes within
// the hour, and while shown the minutes update every 30 s.
Item {
    // Handed in by ModLoader (K26 loader contract).
    required property var store
    required property var theme
    required property var i18n
    id: w
    property bool vertical: false

    // The widget exists while the bar shows it; it watches for its lifetime (a hidden widget must still see an event come).
    Watch { doc: "mod.calendar" }

    readonly property var d: Store.docs["mod.calendar"] || ({})
    readonly property string todayKey: d.today || C.key(new Date())
    readonly property int horizon: 3600
    property real nowS: Date.now() / 1000
    readonly property var ev: C.next(d, nowS, todayKey, horizon)
    readonly property bool has: ev !== null
    readonly property bool running: has && C.isRunning(ev, nowS)
    readonly property string when: !has ? "" : running ? I18n.tr("mod-calendar.now")
        : C.fill(I18n.tr("mod-calendar.min_short"), { n: Math.max(0, Math.ceil((ev.start - nowS) / 60)) })

    // Wake when the shown text can change: every 30 s while shown, else when the next event comes within the hour.
    function arm() {
        var now = Date.now() / 1000
        if (has) { tick.interval = 30000; tick.restart(); return }
        var list = C.upcoming(d, now, todayKey)
        if (list.length === 0) { tick.stop(); return }
        var secs = Math.max(1, Math.min(6 * 3600, list[0].start - horizon - now))
        tick.interval = Math.ceil(secs * 1000)
        tick.restart()
    }
    Timer {
        id: tick
        repeat: false
        onTriggered: { w.nowS = Date.now() / 1000; w.arm() }
    }
    onDChanged: { nowS = Date.now() / 1000; arm() }
    Component.onCompleted: arm()

    visible: has
    implicitWidth: !has ? 0 : w.vertical ? Theme.barH : row.implicitWidth + Theme.gap * 2
    implicitHeight: !has ? 0 : w.vertical ? col.implicitHeight : Theme.controlH
    activeFocusOnTab: has
    Accessible.role: Accessible.Button
    Accessible.name: !has ? "" : C.fill(I18n.tr(running ? "mod-calendar.a11y.widget_now" : "mod-calendar.a11y.widget"),
        { title: ev.title || I18n.tr("mod-calendar.untitled"), n: Math.max(0, Math.ceil((ev.start - nowS) / 60)) })
    // CONTRACT-CHANGE row 203: the clock card opens on its agenda even while another face (media) is current. Row 412: an
    // island whose list leaves the clock out refuses the clock face (`invalid`, K68), and the card then opens the island's
    // own face instead (I203; test-calendar.sh, row 454).
    function open() {
        Store.act("island.expand", { face: "clock" }, function (done, err) {
            if (err && err.kind === "invalid") Store.act("island.expand", {})
        })
    }
    Keys.onReturnPressed: w.open()
    Keys.onEnterPressed: w.open()
    Keys.onSpacePressed: w.open()

    Row {
        id: row
        visible: !w.vertical
        anchors.centerIn: parent
        spacing: Theme.xs
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: Theme.fs + 2
            radius: 1.5
            color: w.has ? (w.ev.color || Theme.accent) : "transparent"
        }
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "event"
            glyph: "▦"
            color: w.running ? Theme.accent : Theme.fg
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 160)
            elide: Text.ElideRight
            textFormat: Text.PlainText
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: w.has ? (w.ev.title || I18n.tr("mod-calendar.untitled")) : ""
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: w.running ? Theme.accent : Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            font.features: ({"tnum": 1})
            text: "· " + w.when
        }
    }
    Column {
        id: col
        visible: w.vertical
        anchors.centerIn: parent
        Icon {
            width: Theme.barH
            name: "event"
            glyph: "▦"
            color: w.running ? Theme.accent : Theme.fg
        }
        Text {
            width: Theme.barH
            horizontalAlignment: Text.AlignHCenter
            color: w.running ? Theme.accent : Theme.fg
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            font.features: ({"tnum": 1})
            text: w.when
        }
    }

    FocusRing { anchors.fill: parent; shown: w.activeFocus; corner: Theme.rSm }
    MouseArea {
        anchors.fill: parent
        enabled: w.has
        cursorShape: Qt.PointingHandCursor
        onClicked: w.open()
    }
}
