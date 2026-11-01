import QtQuick
import Quickshell
import Quickshell.Io
import "../../core"
import ".."

// The tty face (W53.8, docs/ux/styles.md "terminal", "Lock face tty"): the lock as a Linux virtual console's login —
// a dark screen, text from its top left in the look's monospace: an issue line (the shell's name, the host, the
// date and time: what /etc/issue's \n \d \t print), a blank line, `<host> login: <user>` (the user already given, as
// `agetty --autologin`'s prompt would show it), then `Password: ` and the block cursor. Nothing is echoed while the
// password is typed — not a dot, not a star (TextInput.NoEcho), as login(1) does; the cursor stays put. Enter: the
// cursor drops to the next line and nothing is printed while PAM checks (a tty's pause). A wrong password prints
// `Login incorrect` and a fresh login line, the last three attempts kept above as on a real console; PAM's other errors
// and information print as lines; a PAM question (`prompt`) replaces `Password:` and echoes when it asks to. Caps Lock,
// the fingerprint reader, the retry countdown and "daemon disconnected" print as bracketed lines above the prompt. The
// cursor blinks (530 ms) for 10 s after the last key or the focus, then rests lit (Ma): nothing runs at rest. Esc or
// Ctrl+U clear the line (the kill character). The other outputs show the issue line only (`primary` false). Colours from
// roles (rule 4: a phosphor palette makes it green); no animation but the cursor's blink.
FaceBase {
    id: c

    readonly property real s: Math.max(1, Math.min(width / 1440, height / 900))
    readonly property int px: Math.round(Math.max(Theme.fs, 13) * 1.45 * s)
    readonly property bool busy: lock.busy === true
    readonly property bool waiting: remainingMs > 0
    readonly property bool followUp: (lock.prompt || "") !== ""
    readonly property bool echo: lock.prompt_echo === true
    readonly property int failures: Math.max(0, lock.failures || 0)
    readonly property string userName: (user && user.name) ? user.name : String(Quickshell.env("USER") || "")
    property string host: String(Quickshell.env("HOSTNAME") || "")
    readonly property string hostName: host !== "" ? host : "kurashi"
    readonly property string loginLine: I18n.tr("lockui.tty.login").replace("{host}", hostName) + " " + userName
    readonly property string cue: lock.prompt_key ? I18n.tr(lock.prompt_key)
                                  : (lock.prompt ? lock.prompt : I18n.tr("lockui.tty.password"))
    readonly property string errorText: {
        if (lock.message_key === "lock.error.wrong_password") return I18n.tr("lockui.tty.incorrect")
        if (lock.message_key) return I18n.tr(lock.message_key)
        if (lock.pam_message && lock.pam_message.kind === "error") return lock.pam_message.text || ""
        return ""
    }
    // The issue line: the shell, the host, the console; then the date and the time.
    readonly property string issue: I18n.tr("lockui.tty.issue").replace("{host}", hostName)
    readonly property string when: {
        var d = c.clock.date ? new Date(c.clock.date + "T12:00:00") : null
        var day = d ? d.toLocaleDateString(Qt.locale((Store.docs["i18n"] || {}).locale || "en"), I18n.tr("lockui.tty.date_format"))
                    : (c.clock.weekday ?? "")
        return day + "  " + (c.clock.hh ?? "--") + ":" + (c.clock.mm ?? "--")
    }
    // The console's scrollback: the earlier attempts (at most three), each its password line, the error, a new login.
    readonly property var history: {
        var out = []
        var n = Math.min(3, c.failures)
        for (var i = 0; i < n; i++) {
            out.push(I18n.tr("lockui.tty.password"))
            out.push("")
            out.push(i === n - 1 && c.errorText !== "" ? c.errorText : I18n.tr("lockui.tty.incorrect"))
            out.push(c.loginLine)
        }
        if (n === 0 && c.errorText !== "") out.push(c.errorText)
        return out
    }
    // Lines printed above the prompt while their state lasts.
    readonly property var notes: {
        var out = []
        if (!Store.live) out.push("[" + I18n.tr("lockui.disconnected") + "]")
        if (c.lock.pam_message && c.lock.pam_message.kind !== "error" && c.lock.pam_message.text) out.push(c.lock.pam_message.text)
        if (c.fingerprint.available === true)
            out.push(I18n.tr(c.fingerprint.state === "scanning" ? "lockui.fingerprint.scanning" : "lockui.fingerprint.idle"))
        if (c.waiting) out.push(I18n.tr("lockui.retry_in").replace("{s}", Math.ceil(c.remainingMs / 1000)))
        if (c.capsLock) out.push("[" + I18n.tr("lockui.caps_lock") + "]")
        return out
    }
    readonly property color ink: Theme.fg
    readonly property color dim: Qt.alpha(Theme.fg, 0.6)

    color: Theme.color("color.surface_container_lowest", "#000000")

    // The host's name, read once (the kernel's; no polling).
    FileView {
        id: hostFile
        path: "/proc/sys/kernel/hostname"
        printErrors: false
        onLoaded: { var t = String(text() || "").trim(); if (t !== "") c.host = t }
    }

    onFollowUpChanged: { input.text = ""; refocus() }
    onBusyChanged: if (!busy) refocus()
    function refocus() { input.forceActiveFocus(); caret.wake() }
    function submit() {
        if (c.busy || c.waiting) return
        var t = input.text
        input.text = ""             // clear before anything else can observe it
        c.submitted(t)
        t = ""
    }
    function cancel() { input.text = ""; c.cancelled(); input.forceActiveFocus(); caret.wake() }

    FontMetrics { id: fm; font.family: Theme.families[0]; font.pixelSize: c.px }

    component Line: Text {
        width: c.width - 2 * col.x
        color: c.ink
        font.family: Theme.fam(text, Theme.families)
        font.pixelSize: c.px
        wrapMode: Text.WrapAnywhere
        textFormat: Text.PlainText
    }

    Column {
        id: col
        x: Math.round(fm.averageCharacterWidth * 2)
        y: Math.round(fm.height * 1.5)
        spacing: 0

        Line { text: c.issue; color: c.dim }
        Line { text: c.when; color: c.dim }
        Line { text: " " }
        Line { visible: c.primary; text: c.loginLine }
        Repeater {
            model: c.primary ? c.history : []
            Line { required property string modelData; text: modelData === "" ? " " : modelData }
        }
        Repeater {
            model: c.primary ? c.notes : []
            Line { required property string modelData; text: modelData; color: c.dim }
        }
        // The prompt line: the cue, then what is echoed (a PAM question that asks for it; never the password), then the
        // cursor. While PAM checks, the line stands as typed and the cursor waits on the next one.
        Item {
            visible: c.primary
            width: c.width - 2 * col.x
            height: Math.round(fm.height) * (c.busy ? 2 : 1)
            Line {
                id: cueText
                width: implicitWidth
                text: c.cue + " "
            }
            TextInput {
                id: input
                x: cueText.width
                width: Math.max(fm.averageCharacterWidth, parent.width - x)
                height: Math.round(fm.height)
                echoMode: c.echo ? TextInput.Normal : TextInput.NoEcho
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                readOnly: c.busy || c.waiting
                color: c.ink
                selectionColor: Qt.alpha(c.ink, 0.4)
                font.family: Theme.families[0]
                font.pixelSize: c.px
                focus: true
                activeFocusOnTab: true
                cursorDelegate: Item {}
                Accessible.name: c.cue
                Accessible.description: c.busy ? I18n.tr("lockui.checking") : ""
                onAccepted: c.submit()
                onTextChanged: caret.wake()
                onCursorPositionChanged: caret.wake()
                Keys.onEscapePressed: c.cancel()
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_CapsLock) c.capsKey()
                    else if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) { input.text = ""; event.accepted = true }
                }
            }
            // The block cursor: a character cell, after the echoed text (or at the cue's end with no echo), on the next
            // line while busy.
            Rectangle {
                id: caret
                readonly property bool live: input.activeFocus && c.visible
                property bool lit: true
                x: c.busy ? 0 : input.x + (c.echo ? input.cursorRectangle.x : 0)
                y: c.busy ? Math.round(fm.height) : 0
                width: Math.round(fm.averageCharacterWidth)
                height: Math.round(fm.height)
                antialiasing: false
                color: c.ink
                visible: (live || c.busy) && lit
                function wake() {
                    lit = true
                    if (live) { blink.restart(); rest.restart() } else { blink.stop(); rest.stop() }
                }
                onLiveChanged: wake()
                Timer { id: blink; interval: 530; repeat: true; onTriggered: caret.lit = !caret.lit }
                Timer { id: rest; interval: 10000; onTriggered: { blink.stop(); caret.lit = true } }
            }
        }
    }

    MouseArea { anchors.fill: parent; z: -1; onPressed: c.refocus() }
    Component.onCompleted: refocus()
}
