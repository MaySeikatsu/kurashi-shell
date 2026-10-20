import QtQuick
import "../core"

// One lock surface's content (presentational: state in, signals out). The password is held only in
// the TextInput, sent through `submitted` and cleared in the same call stack (K2).
// Styling: tokens only. The shake and the countdown run only while the surface exists (= locked).
Rectangle {
    id: c

    property var lock: ({})             // runtime.lock
    property var clock: ({})            // svc.clock
    property var media: ({})            // svc.media
    property int remainingMs: 0         // local countdown of lock.retry_in_ms (no daemon polling)
    signal submitted(string secret)
    signal cancelled()

    readonly property bool busy: lock.busy === true
    readonly property bool waiting: remainingMs > 0
    readonly property bool followUp: (lock.prompt || "") !== ""
    readonly property bool echo: lock.prompt_echo === true
    readonly property string promptText: lock.prompt_key ? I18n.tr(lock.prompt_key)
                                         : (lock.prompt ? lock.prompt : I18n.tr("lockui.prompt.password"))
    readonly property string messageText: {
        if (waiting) return I18n.tr("lockui.retry_in").replace("{s}", Math.ceil(remainingMs / 1000))
        if (lock.message_key) return I18n.tr(lock.message_key)
        if (lock.pam_message && lock.pam_message.text) return lock.pam_message.text
        return ""
    }
    readonly property bool isError: waiting || !!lock.message_key
                                    || !!(lock.pam_message && lock.pam_message.kind === "error")
    readonly property bool mediaOn: !!(media.title || media.artist)

    color: Theme.surface

    // Keycap chrome (K42): SekaiPop's dot field — dots that grow toward the top-right and bottom-left corners, drawn
    // once per size (the lock surface exists only while locked).
    Canvas {
        anchors.fill: parent
        visible: Theme.keycap
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var g = getContext("2d")
            g.reset()
            g.fillStyle = Qt.alpha(Theme.line, 0.14)
            var step = 26, reach = Math.min(width, height) * 0.9
            for (var y = step / 2; y < height; y += step) {
                for (var x = step / 2; x < width; x += step) {
                    var d1 = Math.hypot(width - x, y), d2 = Math.hypot(x, height - y)
                    var t = Math.max(0, 1 - Math.min(d1, d2) / reach)
                    if (t <= 0.02) continue
                    g.beginPath()
                    g.arc(x, y, 1 + 4 * t, 0, 2 * Math.PI)
                    g.fill()
                }
            }
        }
    }

    function refocus() { field.forceActiveFocus() }
    onFollowUpChanged: { field.text = ""; refocus() }
    onBusyChanged: if (!busy) refocus()

    Column {
        id: col
        anchors.centerIn: parent
        spacing: Theme.pad * 2
        width: 380

        // The time as keys (keycap chrome) or plain tiles (flat), SekaiPop's lock clock.
        KeyClock {
            anchors.horizontalCenter: parent.horizontalCenter
            hh: c.clock.hh ?? "--"
            mm: c.clock.mm ?? "--"
            keyW: 76
            keyH: 104
            digitSize: 72
            animate: c.visible
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                var d = c.clock.date ? new Date(c.clock.date + "T12:00:00") : null
                return d ? d.toLocaleDateString(Qt.locale((Store.docs["i18n"] || {}).locale || "en"), "dddd, d MMMM")
                         : (c.clock.weekday ?? "")
            }
            color: Theme.fg
            font.pixelSize: Theme.fsTitle + 2
            font.weight: Theme.wBold
            font.family: Theme.fam(text, Theme.families)
        }

        // ---- password field -----------------------------------------------------------------
        Rectangle {
            id: box
            width: parent.width
            height: 48
            radius: Theme.keycap ? height / 2 : Theme.rLg
            color: Theme.container
            border.width: Theme.keycap ? Theme.outlineW + 1 : 1
            border.color: c.isError ? Theme.error : (Theme.keycap ? Theme.line : (field.activeFocus ? Theme.fg : Theme.outline))
            // Keycap chrome: the field's hard shadow (a child below the field, drawn behind it).
            Rectangle {
                z: -1
                visible: Theme.shadowDy > 0
                y: Theme.shadowDy
                width: box.width
                height: box.height
                radius: box.radius
                color: c.isError ? Theme.error : Theme.line
            }
            opacity: c.busy ? 0.6 : 1

            // Step lengths are shares of the quick motion token (120 ms calm), so the motion profile
            // and speed apply; under motion none they are 0 and the box does not move.
            SequentialAnimation {
                id: shake
                NumberAnimation { target: box; property: "x"; to: 10; duration: Math.round(Theme.quickMs * 0.42) }
                NumberAnimation { target: box; property: "x"; to: -10; duration: Math.round(Theme.quickMs * 0.67) }
                NumberAnimation { target: box; property: "x"; to: 6; duration: Math.round(Theme.quickMs * 0.58) }
                NumberAnimation { target: box; property: "x"; to: 0; duration: Math.round(Theme.quickMs * 0.42) }
            }
            Connections {
                target: c
                function onIsErrorChanged() { if (c.isError && c.visible) shake.restart() }
            }

            Text {
                anchors { left: parent.left; leftMargin: Theme.pad + 6; verticalCenter: parent.verticalCenter }
                visible: field.text === ""
                text: c.promptText
                color: Theme.dim
                font.pixelSize: Theme.fs
                font.family: Theme.families[0]
            }
            TextInput {
                id: field
                anchors { fill: parent; leftMargin: Theme.pad + 6; rightMargin: Theme.pad + 6 }
                verticalAlignment: TextInput.AlignVCenter
                echoMode: c.echo ? TextInput.Normal : TextInput.Password
                passwordCharacter: "•"
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                readOnly: c.busy || c.waiting
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.families[0]
                selectionColor: Theme.accent
                cursorVisible: activeFocus && !readOnly
                focus: true
                Accessible.name: c.promptText
                onAccepted: {
                    if (text === "") return
                    var s = text
                    text = ""                 // clear before anything else can observe it
                    c.submitted(s)
                    s = ""
                }
                Keys.onEscapePressed: { text = ""; c.cancelled() }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: c.busy ? I18n.tr("lockui.checking") : c.messageText
            visible: text !== ""
            color: c.isError && !c.busy ? Theme.error : Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            visible: c.mediaOn
            text: (c.media.title ?? "") + (c.media.artist ? " — " + c.media.artist : "")
            color: Theme.dim
            opacity: 0.8
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
        }
    }

    // Veil: daemon away while locked. The session stays locked (compositor-enforced); input is inert.
    Text {
        visible: !Store.live
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: Theme.pad * 2 }
        text: I18n.tr("lockui.disconnected")
        color: Theme.dim
        font.pixelSize: Theme.fs
        font.family: Theme.families[0]
    }
    MouseArea { anchors.fill: parent; onPressed: c.refocus() }
}
