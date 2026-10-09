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

    function refocus() { field.forceActiveFocus() }
    onFollowUpChanged: { field.text = ""; refocus() }
    onBusyChanged: if (!busy) refocus()

    Column {
        id: col
        anchors.centerIn: parent
        spacing: Theme.pad * 2
        width: 340

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (c.clock.hh ?? "--") + ":" + (c.clock.mm ?? "--")
            color: Theme.fg
            font.pixelSize: Theme.fsTitle * 4
            font.family: Theme.families[0]
            font.weight: Font.Light
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (c.clock.date ?? "") + "  " + (c.clock.weekday ?? "")
            color: Theme.dim
            font.pixelSize: Theme.fsTitle
            font.family: Theme.families[0]
        }

        // ---- password field -----------------------------------------------------------------
        Rectangle {
            id: box
            width: parent.width
            height: 44
            radius: Theme.rLg
            color: Theme.container
            border.width: 1
            border.color: c.isError ? Theme.accent : (field.activeFocus ? Theme.fg : Theme.outline)
            opacity: c.busy ? 0.6 : 1

            SequentialAnimation {
                id: shake
                NumberAnimation { target: box; property: "x"; to: 10; duration: 50 }
                NumberAnimation { target: box; property: "x"; to: -10; duration: 80 }
                NumberAnimation { target: box; property: "x"; to: 6; duration: 70 }
                NumberAnimation { target: box; property: "x"; to: 0; duration: 50 }
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
            color: c.isError && !c.busy ? Theme.accent : Theme.dim
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
