import QtQuick
import "core"
import "components"

// One output's greeter (W28, docs/ux/greeter.md): the lock screen's content (frontend/components/LockContent.qml,
// unchanged: the user's ground, keycap clock, field, shake and messages) over the user's wallpaper when the greeter may
// read it, with the user and session chips at the bottom left and the power keys at the bottom right. Presentational:
// `g` (Greeter.qml) holds the state. Keyboard: the field has focus; Tab and Shift+Tab cycle field → user → session →
// suspend → restart → power off; Escape returns to the field.
Item {
    id: v
    property var g
    property string wallpaper: ""

    Rectangle { anchors.fill: parent; color: Theme.surface }
    Image {
        id: pic
        anchors.fill: parent
        source: v.wallpaper !== "" ? "file://" + v.wallpaper : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize.width: width
        sourceSize.height: height
        visible: status === Image.Ready
    }

    LockContent {
        id: lc
        anchors.fill: parent
        // Over a picture the surface becomes a veil, so the field and the clock keep their contrast.
        color: pic.visible ? Qt.alpha(Theme.surface, 0.55) : Theme.surface
        lock: v.g.viewLock
        clock: v.g.clock
        onSubmitted: s => v.g.submit(s)
        onCancelled: v.g.cancel()
    }

    readonly property var chain: [lc, userPick, sessionPick, sleepKey, rebootKey, offKey]
    function focusAt(i) {
        var it = chain[(i + chain.length) % chain.length]
        if (it === lc) lc.refocus()
        else if (it.focusChip) it.focusChip()
        else it.forceActiveFocus()
    }
    function current() {
        if (userPick.chipFocused) return 1
        if (sessionPick.chipFocused) return 2
        for (var i = 3; i < chain.length; i++) if (chain[i].activeFocus) return i
        return 0
    }
    Keys.onTabPressed: focusAt(current() + 1)
    Keys.onBacktabPressed: focusAt(current() - 1)
    Keys.onEscapePressed: lc.refocus()

    Row {
        id: left
        anchors { left: parent.left; bottom: parent.bottom; margins: Theme.pad * 2 }
        spacing: Theme.gap
        Picker {
            id: userPick
            icon: "person"
            enabled: !v.g.launching
            options: v.g.users.map(function (u) { return { label: u.display } })
            current: v.g.userIndex
            a11y: I18n.tr("greeter.user") + ": " + label
            onChosen: i => { v.g.pickUser(i); lc.refocus() }
        }
        Picker {
            id: sessionPick
            icon: "desktop_windows"
            enabled: !v.g.launching
            options: v.g.sessions.length > 0 ? v.g.sessions.map(function (s) { return { label: s.name } })
                                             : [{ label: I18n.tr("greeter.no_sessions") }]
            current: v.g.sessions.length > 0 ? v.g.sessionIndex : 0
            a11y: I18n.tr("greeter.session") + ": " + label
            onChosen: i => { v.g.pickSession(i); lc.refocus() }
        }
    }
    Row {
        anchors { right: parent.right; bottom: parent.bottom; margins: Theme.pad * 2 }
        spacing: Theme.gap
        IconButton {
            id: sleepKey
            icon: "bedtime"; glyph: "☾"
            a11y: I18n.tr("greeter.power.suspend")
            activeFocusOnTab: false
            onClicked: v.g.powerAction("suspend")
        }
        IconButton {
            id: rebootKey
            icon: "restart_alt"; glyph: "↻"
            a11y: I18n.tr("greeter.power.reboot")
            activeFocusOnTab: false
            onClicked: v.g.powerAction("reboot")
        }
        IconButton {
            id: offKey
            icon: "power_settings_new"; glyph: "⏻"
            a11y: I18n.tr("greeter.power.poweroff")
            activeFocusOnTab: false
            onClicked: v.g.powerAction("poweroff")
        }
    }
}
