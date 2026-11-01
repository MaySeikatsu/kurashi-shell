import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../core"
import ".."
import "../decor"

// The hollow face (W53.6, docs/ux/styles.md §9.4 "Lock face hollow"): a still, foggy deep. A blue-black ground with banks
// of pale fog drifting nowhere (painted once), the time in engraved capitals at the top centre over an ornament rule and
// the date in a book serif; low in the centre the field framed by an ornament above and below it (Filigree.qml: our
// own, in the spirit of Hollow Knight's menu dividers, never its art), the prompt in small capitals on the field. A wrong
// password fades a pale line in under the lower ornament; Caps Lock, busy, the countdown and PAM's information are that
// line too; a PAM question relabels the prompt (echo when it asks); "daemon disconnected" under the date. The other
// outputs show the fog and the time. Colours from roles (rule 4): `surface` (the deep), `secondary` (the fog's blue),
// `on_surface` (bone white), `error`. Ma: painted once; the message's fade is one-shot (none under reduce motion).
FaceBase {
    id: c

    readonly property real s: Math.max(1, Math.min(width / 1440, height / 900))
    readonly property bool busy: lock.busy === true
    readonly property bool waiting: remainingMs > 0
    readonly property bool followUp: (lock.prompt || "") !== ""
    readonly property bool echo: lock.prompt_echo === true
    readonly property string cue: lock.prompt_key ? I18n.tr(lock.prompt_key)
                                  : (lock.prompt ? lock.prompt : I18n.tr("lockui.hollow.prompt"))
    readonly property string errorText: {
        if (lock.message_key) return I18n.tr(lock.message_key)
        if (lock.pam_message && lock.pam_message.kind === "error") return lock.pam_message.text || ""
        return ""
    }
    readonly property string statusText: {
        if (busy) return I18n.tr("lockui.checking")
        if (waiting) return I18n.tr("lockui.retry_in").replace("{s}", Math.ceil(remainingMs / 1000))
        if (capsLock) return I18n.tr("lockui.caps_lock")
        if (lock.pam_message && lock.pam_message.kind !== "error" && lock.pam_message.text) return lock.pam_message.text
        if (fingerprint.available === true)
            return I18n.tr(fingerprint.state === "scanning" ? "lockui.fingerprint.scanning" : "lockui.fingerprint.idle")
        return ""
    }
    readonly property string line: errorText !== "" ? errorText : statusText
    readonly property string userName: (user && user.name) ? user.name : String(Quickshell.env("USER") || "")
    readonly property string fam: Theme.fam(cue, Theme.families)
    readonly property string caps: Theme.tok("font.title", "") || fam
    readonly property color deep: Theme.color("color.surface_container_lowest", "#0a0d13")
    readonly property color mid: Theme.color("color.surface", "#12161e")
    readonly property color fog: Theme.secondary
    readonly property color bone: Theme.fg
    readonly property bool moves: Theme.motionKind !== "none"

    color: deep

    onFollowUpChanged: { input.text = ""; refocus() }
    onBusyChanged: if (!busy) refocus()
    onLineChanged: if (line !== "" && c.moves && c.visible) { msg.opacity = 0; reveal.restart() }
    function refocus() { input.forceActiveFocus() }
    function submit() {
        if (input.text === "" || c.busy || c.waiting) return
        var t = input.text
        input.text = ""
        c.submitted(t)
        t = ""
    }
    function cancel() { input.text = ""; c.cancelled(); input.forceActiveFocus() }
    NumberAnimation { id: reveal; target: msg; property: "opacity"; from: 0; to: 1; duration: 700; easing.type: Easing.InOutSine }

    // ---- the fog (static) --------------------------------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: c.deep }
            GradientStop { position: 0.55; color: c.mid }
            GradientStop { position: 1; color: c.deep }
        }
    }
    // Banks of fog: wide, pale-blue glows (x, y as shares of the output; reach; strength).
    component Bank: ShapePath {
        property real fx: 0.5
        property real fy: 0.5
        property real reach: 0.5
        property real strength: 0.2
        strokeColor: "transparent"
        fillGradient: RadialGradient {
            centerX: c.width * fx; centerY: c.height * fy
            focalX: centerX; focalY: centerY
            centerRadius: c.height * reach
            GradientStop { position: 0; color: Qt.alpha(Qt.lighter(c.fog, 1.25), strength) }
            GradientStop { position: 1; color: Qt.alpha(c.fog, 0) }
        }
        startX: 0; startY: 0
        PathLine { x: c.width; y: 0 }
        PathLine { x: c.width; y: c.height }
        PathLine { x: 0; y: c.height }
        PathLine { x: 0; y: 0 }
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        Bank { fx: 0.18; fy: 0.78; reach: 0.55; strength: 0.22 }
        Bank { fx: 0.82; fy: 0.7; reach: 0.5; strength: 0.2 }
        Bank { fx: 0.5; fy: 0.95; reach: 0.7; strength: 0.26 }
        Bank { fx: 0.35; fy: 0.25; reach: 0.45; strength: 0.1 }
        Bank { fx: 0.75; fy: 0.2; reach: 0.4; strength: 0.08 }
    }

    // ---- the time over an ornament, top centre (every output) --------------------------------------------------------
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.1)
        spacing: Math.round(6 * c.s)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (c.clock.hh ?? "--") + ":" + (c.clock.mm ?? "--")
            color: c.bone
            font.family: c.caps
            font.pixelSize: Math.round(64 * c.s)
            font.letterSpacing: 4 * c.s
        }
        Filigree {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(260 * c.s)
            height: Math.round(14 * c.s)
            ink: Qt.alpha(c.bone, 0.85)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                var d = c.clock.date ? new Date(c.clock.date + "T12:00:00") : null
                return d ? d.toLocaleDateString(Qt.locale((Store.docs["i18n"] || {}).locale || "en"), "dddd d MMMM") : (c.clock.weekday ?? "")
            }
            color: Qt.alpha(c.bone, 0.72)
            font.family: c.fam
            font.pixelSize: Math.round(19 * c.s)
            font.italic: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !Store.live
            text: I18n.tr("lockui.disconnected")
            color: c.bone
            font.family: c.fam
            font.pixelSize: Math.round(14 * c.s)
        }
    }

    // ---- the field between two ornaments, low in the centre (the focused output) --------------------------------------
    Column {
        visible: c.primary
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height - height - Math.max(90, 110 * c.s))
        spacing: Math.round(12 * c.s)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: c.userName.toUpperCase()
            color: Qt.alpha(c.bone, 0.85)
            font.family: c.caps
            font.pixelSize: Math.round(16 * c.s)
            font.letterSpacing: 3 * c.s
        }
        Filigree {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(360 * c.s)
            height: Math.round(14 * c.s)
            ink: c.bone
        }
        Item {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(320 * c.s)
            height: Math.round(36 * c.s)
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.alpha(c.fog, 0) }
                    GradientStop { position: 0.5; color: Qt.alpha(c.fog, input.activeFocus ? 0.16 : 0.1) }
                    GradientStop { position: 1; color: Qt.alpha(c.fog, 0) }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: input.text === "" && input.preeditText === ""
                text: c.cue
                color: Qt.alpha(c.bone, 0.55)
                font.family: c.caps
                font.pixelSize: Math.round(14 * c.s)
                font.letterSpacing: 2.5 * c.s
                font.capitalization: Font.AllUppercase
            }
            TextInput {
                id: input
                anchors { fill: parent; leftMargin: Math.round(24 * c.s); rightMargin: Math.round(24 * c.s) }
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                echoMode: c.echo ? TextInput.Normal : TextInput.Password
                passwordCharacter: "◆"
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                readOnly: c.busy || c.waiting
                color: c.bone
                selectionColor: Qt.alpha(c.fog, 0.5)
                selectedTextColor: c.bone
                font.family: c.fam
                font.pixelSize: Math.round(c.echo ? 18 * c.s : 12 * c.s)
                font.letterSpacing: c.echo ? 0 : 6
                clip: true
                focus: true
                activeFocusOnTab: true
                cursorVisible: activeFocus && !readOnly
                Accessible.name: c.cue
                onAccepted: c.submit()
                Keys.onEscapePressed: c.cancel()
                Keys.onPressed: event => { if (event.key === Qt.Key_CapsLock) c.capsKey() }
            }
        }
        Filigree {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(360 * c.s)
            height: Math.round(14 * c.s)
            ink: c.bone
            transform: Scale { origin.y: Math.round(7 * c.s); yScale: -1 }
        }
        Text {
            id: msg
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(440 * c.s)
            height: Math.max(implicitHeight, Math.round(20 * c.s))
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: c.line
            color: c.errorText !== "" ? Qt.lighter(Theme.error, 1.15) : Qt.alpha(c.bone, 0.78)
            font.family: c.fam
            font.pixelSize: Math.round(16 * c.s)
            font.italic: c.errorText === ""
            Accessible.role: c.errorText !== "" ? Accessible.AlertMessage : Accessible.StaticText
            Accessible.name: text
        }
    }

    MouseArea { anchors.fill: parent; z: -1; onPressed: c.refocus() }
}
