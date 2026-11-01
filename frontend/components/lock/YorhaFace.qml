import QtQuick
import Quickshell
import "../../core"
import ".."
import "../decor"

// The yorha face (W53.6, docs/ux/styles.md §9.2 "Lock face yorha"): a terminal-like connect panel in the spirit of
// NieR:Automata's system screens, never its text or art. The parchment ground with its faint grid and scanlines; a
// centred panel: a header band (the square bullet and CONNECT in capitals over the thick-and-thin rule) and then a log of
// lines, each a label, a dotted leader and a value — host, user, time, link status — and last the passcode line, the
// field, a dark block wiping in under it while it has the keyboard. The lines appear one after another once as the face
// appears (all at once under reduce motion); the field has the keyboard from the first frame. Status words: STANDBY,
// VERIFYING, DENIED (the line inverted), RETRY IN n s, CAPS LOCK ON (a line of its own), a PAM question as the passcode
// line's label (echo when it asks), and DISCONNECTED when the daemon is gone. Other outputs show the ground and the header
// with the time. Colours from roles (rule 4): `surface` (parchment), `on_surface` (ink), `error`; idle = 0 frames.
FaceBase {
    id: c

    readonly property real s: Math.max(1, Math.min(width / 1440, height / 900))
    readonly property bool busy: lock.busy === true
    readonly property bool waiting: remainingMs > 0
    readonly property bool followUp: (lock.prompt || "") !== ""
    readonly property bool echo: lock.prompt_echo === true
    readonly property string errorText: {
        if (lock.message_key) return I18n.tr(lock.message_key)
        if (lock.pam_message && lock.pam_message.kind === "error") return lock.pam_message.text || ""
        return ""
    }
    readonly property bool denied: errorText !== ""
    readonly property string status: !Store.live ? I18n.tr("lockui.yorha.disconnected")
        : busy ? I18n.tr("lockui.yorha.verifying")
        : waiting ? I18n.tr("lockui.yorha.retry").replace("{s}", Math.ceil(remainingMs / 1000))
        : denied ? I18n.tr("lockui.yorha.denied")
        : I18n.tr("lockui.yorha.standby")
    readonly property string info: {
        if (lock.pam_message && lock.pam_message.kind !== "error" && lock.pam_message.text) return lock.pam_message.text
        if (fingerprint.available === true)
            return I18n.tr(fingerprint.state === "scanning" ? "lockui.fingerprint.scanning" : "lockui.fingerprint.idle")
        return ""
    }
    readonly property string userName: (user && user.name) ? user.name : String(Quickshell.env("USER") || "")
    readonly property string host: String(Quickshell.env("HOSTNAME") || "") || "暮らし"
    readonly property string fam: Theme.fam(userName, Theme.families)
    readonly property string head: Theme.tok("font.title", "") || fam
    readonly property color paper: Theme.color("color.surface", "#cdc8b0")
    readonly property color ink: Theme.fg
    readonly property color band: Theme.color("color.surface_container_high", "#bab29a")
    readonly property bool moves: Theme.motionKind !== "none"
    readonly property real fs: Math.round(15 * s)
    // How many log lines are shown (the reveal runs once).
    property int shown: moves ? 0 : 99

    color: paper

    onFollowUpChanged: { input.text = ""; refocus() }
    onBusyChanged: if (!busy) refocus()
    Component.onCompleted: if (moves) reveal.start()
    function refocus() { input.forceActiveFocus() }
    function submit() {
        if (input.text === "" || c.busy || c.waiting) return
        var t = input.text
        input.text = ""
        c.submitted(t)
        t = ""
    }
    function cancel() { input.text = ""; c.cancelled(); input.forceActiveFocus() }
    Timer {
        id: reveal
        interval: 70
        repeat: true
        onTriggered: { c.shown += 1; if (c.shown >= 8) stop() }
    }

    // ---- the ground: parchment and the grid (static) ----------------------------------------------------------
    Pattern { anchors.fill: parent; kind: "grid"; strength: 0.07 }

    // A log line: the label, a dotted leader, the value; `inverse` draws it as the selection block.
    component Line: Item {
        id: ln
        property int order: 0
        property string label: ""
        property string value: ""
        property bool inverse: false
        width: panel.inner
        height: Math.round(c.fs * 2)
        visible: c.shown > order
        Rectangle {
            anchors.fill: parent
            color: ln.inverse ? c.ink : Qt.alpha(c.band, 0.55)
        }
        Bullet {
            x: Math.round(c.fs * 0.6)
            anchors.verticalCenter: parent.verticalCenter
            kind: "square"
            size: Math.round(c.fs * 0.4)
            ink: ln.inverse ? c.paper : c.ink
        }
        Text {
            id: lab
            x: Math.round(c.fs * 1.6)
            anchors.verticalCenter: parent.verticalCenter
            text: ln.label.toUpperCase()
            color: ln.inverse ? c.paper : c.ink
            font.family: c.head
            font.pixelSize: c.fs
            font.letterSpacing: Math.round(c.fs * 0.12)
        }
        Text {
            anchors { left: lab.right; leftMargin: Math.round(c.fs * 0.5); right: val.left; rightMargin: Math.round(c.fs * 0.5)
                      verticalCenter: parent.verticalCenter }
            text: "· · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·"
            clip: true
            elide: Text.ElideNone
            color: Qt.alpha(ln.inverse ? c.paper : c.ink, 0.45)
            font.family: c.fam
            font.pixelSize: c.fs
        }
        Text {
            id: val
            anchors { right: parent.right; rightMargin: Math.round(c.fs * 0.8); verticalCenter: parent.verticalCenter }
            text: ln.value
            color: ln.inverse ? c.paper : c.ink
            font.family: c.head
            font.pixelSize: c.fs
            font.letterSpacing: Math.round(c.fs * 0.08)
        }
    }

    Column {
        id: panel
        readonly property real inner: Math.round(560 * c.s)
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.24)
        spacing: Math.round(6 * c.s)
        // The header: the bullet and CONNECT, the time at its end, the thick-and-thin rule under it.
        Item {
            width: panel.inner
            height: Math.round(c.fs * 2.8)
            Bullet {
                anchors.verticalCenter: parent.verticalCenter
                kind: "square"
                size: Math.round(c.fs * 0.7)
                ink: c.ink
            }
            Text {
                x: Math.round(c.fs * 1.4)
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("lockui.yorha.title").toUpperCase()
                color: c.ink
                font.family: c.head
                font.pixelSize: Math.round(c.fs * 1.9)
                font.letterSpacing: Math.round(c.fs * 0.3)
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: (c.clock.hh ?? "--") + ":" + (c.clock.mm ?? "--")
                color: c.ink
                font.family: c.head
                font.pixelSize: Math.round(c.fs * 1.9)
                font.letterSpacing: Math.round(c.fs * 0.15)
            }
        }
        Rule { width: panel.inner; kind: "double"; ink: c.ink }
        Item { width: 1; height: Math.round(6 * c.s) }
        Line { order: 0; label: I18n.tr("lockui.yorha.host"); value: c.host }
        Line { order: 1; label: I18n.tr("lockui.yorha.user"); value: c.userName }
        Line {
            order: 2
            label: I18n.tr("lockui.yorha.date")
            value: {
                var d = c.clock.date ? new Date(c.clock.date + "T12:00:00") : null
                return (d ? d.toLocaleDateString(Qt.locale((Store.docs["i18n"] || {}).locale || "en"), "ddd d MMM yyyy") : (c.clock.weekday ?? "")).toUpperCase()
            }
        }
        Line { order: 3; label: I18n.tr("lockui.yorha.link"); value: c.status; inverse: c.denied || !Store.live }
        Line { order: 4; visible: c.shown > 4 && c.capsLock; label: I18n.tr("lockui.yorha.caps"); value: I18n.tr("lockui.yorha.on"); inverse: true }
        Line { order: 4; visible: c.shown > 4 && c.info !== ""; label: I18n.tr("lockui.yorha.info"); value: c.info }
        Line { order: 4; visible: c.shown > 4 && c.denied && c.errorText !== I18n.tr("lockui.yorha.denied"); label: I18n.tr("lockui.yorha.reason"); value: c.errorText }
        Item { width: 1; height: Math.round(6 * c.s) }
        // The passcode line: the field. While it has the keyboard a dark block lies under it, the text inverted.
        Item {
            id: field
            visible: c.primary
            width: panel.inner
            height: Math.round(c.fs * 2.6)
            readonly property bool lit: input.activeFocus && !c.busy && !c.waiting
            property real reach: lit ? 1 : 0
            Behavior on reach { enabled: c.moves; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Rectangle { anchors.fill: parent; color: Qt.alpha(c.band, 0.55) }
            Rectangle { width: Math.round(parent.width * field.reach); height: parent.height; color: c.ink }
            Bullet {
                x: Math.round(c.fs * 0.6)
                anchors.verticalCenter: parent.verticalCenter
                kind: "square"
                size: Math.round(c.fs * 0.4)
                ink: field.reach > 0.5 ? c.paper : c.ink
            }
            Text {
                id: plab
                x: Math.round(c.fs * 1.6)
                anchors.verticalCenter: parent.verticalCenter
                text: (c.followUp ? (lock.prompt_key ? I18n.tr(lock.prompt_key) : lock.prompt) : I18n.tr("lockui.yorha.passcode")).toUpperCase()
                color: field.reach > 0.5 ? c.paper : c.ink
                font.family: c.head
                font.pixelSize: c.fs
                font.letterSpacing: Math.round(c.fs * 0.12)
            }
            TextInput {
                id: input
                anchors { left: plab.right; leftMargin: Math.round(c.fs); right: parent.right; rightMargin: Math.round(c.fs * 0.8)
                          verticalCenter: parent.verticalCenter }
                horizontalAlignment: TextInput.AlignRight
                echoMode: c.echo ? TextInput.Normal : TextInput.Password
                passwordCharacter: "■"
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                readOnly: c.busy || c.waiting
                color: field.reach > 0.5 ? c.paper : c.ink
                selectionColor: Qt.alpha(c.paper, 0.4)
                selectedTextColor: c.ink
                font.family: c.head
                font.pixelSize: c.echo ? c.fs : Math.round(c.fs * 0.7)
                font.letterSpacing: c.echo ? 0 : Math.round(c.fs * 0.3)
                clip: true
                focus: true
                activeFocusOnTab: true
                cursorVisible: activeFocus && !readOnly
                cursorDelegate: Rectangle { width: Math.round(c.fs * 0.55); height: Math.round(c.fs * 1.1); color: field.reach > 0.5 ? c.paper : c.ink }
                Accessible.name: plab.text
                onAccepted: c.submit()
                Keys.onEscapePressed: c.cancel()
                Keys.onPressed: event => { if (event.key === Qt.Key_CapsLock) c.capsKey() }
            }
        }
        Rule { visible: c.primary; width: panel.inner; kind: "single"; ink: Qt.alpha(c.ink, 0.6) }
    }

    MouseArea { anchors.fill: parent; z: -1; onPressed: c.refocus() }
}
