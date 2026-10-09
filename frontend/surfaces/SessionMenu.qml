import QtQuick
import "../core"

// Session menu (runtime.ui.panel === "session", opened by the `session.menu` action), shown inside
// the Stage card. A pure view: each entry sends one daemon action and nothing else. Lock runs at
// once; the others need a second press within 3 s, which sends {confirm: true} (the daemon refuses
// them without it). Keyboard: Up/Down or Tab move, Enter runs, Esc closes. On success the panel
// closes (ui.close); on failure the daemon's text is shown here.
Item {
    id: menu

    // Stage sets this while the menu is on screen. Leaving it disarms and clears the error: an arm
    // must not survive a close, or reopening the menu would make one press destructive.
    property bool active: false

    // Keys are spelled out so every string is greppable against i18n/ (rule 8).
    readonly property var entries: [
        { label: "action.session.lock", confirm: "", action: "session.lock", destructive: false },
        { label: "action.session.suspend", confirm: "frontend.session.confirm.suspend", action: "session.suspend", destructive: true },
        { label: "action.session.logout", confirm: "frontend.session.confirm.logout", action: "session.logout", destructive: true },
        { label: "action.session.reboot", confirm: "frontend.session.confirm.reboot", action: "session.reboot", destructive: true },
        { label: "action.session.poweroff", confirm: "frontend.session.confirm.poweroff", action: "session.poweroff", destructive: true }
    ]
    property int cursor: 0
    property int armed: -1      // entry index waiting for its confirming press
    property bool busy: false   // an action is in flight; presses are ignored until it answers
    property string errText: ""

    implicitWidth: 328
    implicitHeight: body.implicitHeight

    onActiveChanged: {
        if (active) Qt.callLater(function () { menu.forceActiveFocus() })
        else { disarm(); errText = "" }
    }

    // Runs only for the 3 s after a first press (Ma: nothing ticks while the menu is not armed).
    Timer {
        id: disarmTimer
        interval: 3000
        onTriggered: menu.armed = -1
    }
    function disarm() {
        disarmTimer.stop()
        armed = -1
    }

    function activate(i) {
        if (busy) return
        var e = entries[i]
        if (e.destructive && armed !== i) {
            errText = ""
            armed = i
            disarmTimer.restart()
            return
        }
        disarm()
        errText = ""
        busy = true
        Store.act(e.action, e.destructive ? { confirm: true } : {}, function (done, err) {
            busy = false
            if (err) errText = I18n.tr(err.msg || "") || I18n.tr("frontend.session.failed")
            else Store.act("ui.close")
        })
    }

    focus: true
    Keys.onPressed: event => {
        var n = entries.length
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) cursor = (cursor + 1) % n
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) cursor = (cursor + n - 1) % n
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) activate(cursor)
        else if (event.key === Qt.Key_Escape) Store.act("ui.close")
        else return
        event.accepted = true
    }

    Column {
        id: body
        width: menu.implicitWidth
        spacing: Theme.gap

        Text {
            color: Theme.fg
            font.pixelSize: Theme.fsTitle
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("action.session.menu")
        }
        Repeater {
            model: menu.entries
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                width: body.width
                height: 32
                radius: Theme.rSm
                color: menu.cursor === index ? Theme.containerHigh : "transparent"
                border.width: menu.cursor === index ? 1 : 0
                border.color: menu.armed === index ? Theme.accent : Theme.outline

                Text {
                    x: Theme.pad
                    anchors.verticalCenter: parent.verticalCenter
                    color: menu.armed === index ? Theme.accent : Theme.fg
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr(menu.armed === index ? row.modelData.confirm : row.modelData.label)
                }
                HoverHandler { onHoveredChanged: if (hovered) menu.cursor = row.index }
                TapHandler { onTapped: menu.activate(row.index) }
            }
        }
        Text {
            width: body.width
            visible: menu.errText !== ""
            wrapMode: Text.WordWrap
            color: Theme.color("color.error", "#c9404b")
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: menu.errText
        }
        Text {
            width: body.width
            color: Theme.dim
            font.pixelSize: Theme.fs - 2
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("frontend.session.hint")
        }
    }
}
