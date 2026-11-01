import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../core"
import ".."
import "../decor"

// The bonfire face (W53.6, docs/ux/styles.md §9.3 "Lock face bonfire"): a resting place in the dark. A near-black ground
// warming toward the lower middle, where an ember glow breathes up — it flickers a few times as the face appears and
// then rests (0 frames idle; still under reduce motion) — never the game's bonfire art. The time and date stand small at
// the top centre in the look's serif; the field sits low in the centre on a dark band held between two gold hairlines
// that fade at their ends, the prompt in small capitals above it. A wrong password shows "Try again" in a large serif
// across a dark band through the middle of the screen, fading in, holding and fading out (at once and until the next key
// under reduce motion) — never the game's death message — with the reason under the field. Caps Lock, busy, the
// countdown and PAM's information are a line under the field; a PAM question relabels the prompt (echo when it asks);
// "daemon disconnected" under the date. The other outputs show the ground, the ember and the time. Colours from roles
// (rule 4): `surface` (the dark), `tertiary` (the ember), `accent` (gold), `on_surface` (bone), `error`.
FaceBase {
    id: c

    readonly property real s: Math.max(1, Math.min(width / 1440, height / 900))
    readonly property bool busy: lock.busy === true
    readonly property bool waiting: remainingMs > 0
    readonly property bool followUp: (lock.prompt || "") !== ""
    readonly property bool echo: lock.prompt_echo === true
    readonly property string cue: lock.prompt_key ? I18n.tr(lock.prompt_key)
                                  : (lock.prompt ? lock.prompt : I18n.tr("lockui.bonfire.prompt"))
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
    readonly property string userName: (user && user.name) ? user.name : String(Quickshell.env("USER") || "")
    readonly property string fam: Theme.fam(cue, Theme.families)
    readonly property string serif: Theme.tok("font.title", "") || fam
    readonly property color dark: Theme.color("color.surface", "#14110d")
    readonly property color ember: Theme.tertiary
    readonly property color gold: Theme.accent
    readonly property color bone: Theme.fg
    // The message's red: the error role's hue, deep and dull (a lament, not an alarm).
    readonly property color lament: Qt.hsla(Math.max(0, Theme.error.hslHue), 0.55, Theme.darkScheme ? 0.42 : 0.36, 1)
    readonly property bool moves: Theme.motionKind !== "none"
    // The ember's breath: 1 at rest; the flicker runs once.
    property real glow: 1

    color: dark

    onFollowUpChanged: { input.text = ""; refocus() }
    onBusyChanged: if (!busy) refocus()
    onErrorTextChanged: {
        if (errorText === "") return
        if (c.moves && c.visible) againAnim.restart()
        else banner.opacity = 1
    }
    Component.onCompleted: {
        if (c.moves) flicker.start()
        if (errorText !== "") { if (c.moves) againAnim.start(); else banner.opacity = 1 }
    }
    function refocus() { input.forceActiveFocus() }
    function submit() {
        if (input.text === "" || c.busy || c.waiting) return
        var t = input.text
        input.text = ""
        c.submitted(t)
        t = ""
    }
    function cancel() { input.text = ""; c.cancelled(); input.forceActiveFocus() }

    SequentialAnimation {
        id: flicker
        NumberAnimation { target: c; property: "glow"; to: 0.72; duration: 140; easing.type: Easing.InOutSine }
        NumberAnimation { target: c; property: "glow"; to: 1.0; duration: 220; easing.type: Easing.InOutSine }
        NumberAnimation { target: c; property: "glow"; to: 0.8; duration: 120; easing.type: Easing.InOutSine }
        NumberAnimation { target: c; property: "glow"; to: 0.96; duration: 260; easing.type: Easing.InOutSine }
        NumberAnimation { target: c; property: "glow"; to: 0.84; duration: 180; easing.type: Easing.InOutSine }
        NumberAnimation { target: c; property: "glow"; to: 1.0; duration: 420; easing.type: Easing.OutSine }
    }
    SequentialAnimation {
        id: againAnim
        NumberAnimation { target: banner; property: "opacity"; from: 0; to: 1; duration: 1100; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 1400 }
        NumberAnimation { target: banner; property: "opacity"; to: 0; duration: 1800; easing.type: Easing.InOutSine }
    }

    // ---- the ground: dark, warmer toward the ember (static) ---------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.darker(c.dark, 1.5) }
            GradientStop { position: 0.6; color: c.dark }
            GradientStop { position: 1; color: Qt.tint(c.dark, Qt.alpha(c.ember, 0.08)) }
        }
    }
    // ---- the ember: a warm halo and a hot core, low in the middle -----------------------------------------------------
    Item {
        id: fire
        x: Math.round(c.width / 2 - width / 2)
        y: Math.round(c.height * 0.72 - height / 2)
        width: Math.round(c.height * 0.9)
        height: width
        opacity: 0.35 + 0.65 * c.glow
        scale: 0.94 + 0.06 * c.glow
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"
                fillGradient: RadialGradient {
                    centerX: fire.width / 2; centerY: fire.height / 2
                    focalX: centerX; focalY: centerY + fire.height * 0.06
                    centerRadius: fire.width / 2
                    GradientStop { position: 0; color: Qt.alpha(Qt.lighter(c.ember, 1.5), 0.55) }
                    GradientStop { position: 0.12; color: Qt.alpha(c.ember, 0.4) }
                    GradientStop { position: 0.4; color: Qt.alpha(Qt.darker(c.ember, 1.6), 0.16) }
                    GradientStop { position: 1; color: Qt.alpha(c.ember, 0) }
                }
                startX: 0; startY: 0
                PathLine { x: fire.width; y: 0 }
                PathLine { x: fire.width; y: fire.height }
                PathLine { x: 0; y: fire.height }
                PathLine { x: 0; y: 0 }
            }
        }
    }

    // ---- the time, top centre (every output) -------------------------------------------------------------------------
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.08)
        spacing: Math.round(4 * c.s)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (c.clock.hh ?? "--") + ":" + (c.clock.mm ?? "--")
            color: c.bone
            font.family: c.serif
            font.pixelSize: Math.round(54 * c.s)
            font.weight: Font.Normal
            font.letterSpacing: 2 * c.s
        }
        Rule {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(220 * c.s)
            kind: "single"
            fade: true
            ink: c.gold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                var d = c.clock.date ? new Date(c.clock.date + "T12:00:00") : null
                return d ? d.toLocaleDateString(Qt.locale((Store.docs["i18n"] || {}).locale || "en"), "dddd d MMMM") : (c.clock.weekday ?? "")
            }
            color: Qt.alpha(c.bone, 0.75)
            font.family: c.serif
            font.pixelSize: Math.round(17 * c.s)
            font.letterSpacing: 1.5 * c.s
            font.capitalization: Font.SmallCaps
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !Store.live
            text: I18n.tr("lockui.disconnected")
            color: c.bone
            font.family: c.fam
            font.pixelSize: Math.round(13 * c.s)
        }
    }

    // ---- "Try again": a large serif across a dark band through the middle ---------------------------------------------
    Item {
        id: banner
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -Math.round(parent.height * 0.06)
        width: parent.width
        height: Math.round(parent.height * 0.2)
        opacity: 0
        visible: opacity > 0
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) }
                GradientStop { position: 0.3; color: Qt.rgba(0, 0, 0, 0.7) }
                GradientStop { position: 0.7; color: Qt.rgba(0, 0, 0, 0.7) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
            }
        }
        Text {
            anchors.centerIn: parent
            text: I18n.tr("lockui.bonfire.again")
            color: c.lament
            font.family: c.serif
            font.pixelSize: Math.round(76 * c.s)
            font.letterSpacing: 3 * c.s
            Accessible.role: Accessible.AlertMessage
            Accessible.name: text
        }
    }

    // ---- the field, low in the centre (the focused output) ------------------------------------------------------------
    Column {
        visible: c.primary
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height - height - Math.max(84, 96 * c.s))
        spacing: Math.round(8 * c.s)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: c.userName
            color: Qt.alpha(c.bone, 0.8)
            font.family: c.serif
            font.pixelSize: Math.round(15 * c.s)
            font.letterSpacing: 1.5 * c.s
            font.capitalization: Font.SmallCaps
        }
        Item {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(400 * c.s)
            height: Math.round(40 * c.s)
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) }
                    GradientStop { position: 0.15; color: Qt.alpha(Qt.darker(c.dark, 1.4), 0.85) }
                    GradientStop { position: 0.85; color: Qt.alpha(Qt.darker(c.dark, 1.4), 0.85) }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
                }
            }
            Rule { width: parent.width; kind: "single"; fade: true; ink: Qt.alpha(c.gold, input.activeFocus ? 1 : 0.6) }
            Rule { width: parent.width; y: parent.height - height; kind: "single"; fade: true; ink: Qt.alpha(c.gold, input.activeFocus ? 1 : 0.6) }
            Text {
                anchors.centerIn: parent
                visible: input.text === "" && input.preeditText === ""
                text: c.cue
                color: Qt.alpha(c.bone, 0.55)
                font.family: c.serif
                font.pixelSize: Math.round(16 * c.s)
                font.letterSpacing: 1.5 * c.s
                font.capitalization: Font.SmallCaps
            }
            TextInput {
                id: input
                anchors { fill: parent; leftMargin: Math.round(56 * c.s); rightMargin: Math.round(56 * c.s) }
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                echoMode: c.echo ? TextInput.Normal : TextInput.Password
                passwordCharacter: "•"
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                readOnly: c.busy || c.waiting
                color: c.bone
                selectionColor: Qt.alpha(c.gold, 0.4)
                selectedTextColor: c.bone
                font.family: c.serif
                font.pixelSize: Math.round(18 * c.s)
                font.letterSpacing: c.echo ? 0 : 4
                clip: true
                focus: true
                activeFocusOnTab: true
                cursorVisible: activeFocus && !readOnly
                Accessible.name: c.cue
                onAccepted: c.submit()
                onTextChanged: if (text !== "" && !againAnim.running) banner.opacity = 0
                Keys.onEscapePressed: c.cancel()
                Keys.onPressed: event => { if (event.key === Qt.Key_CapsLock) c.capsKey() }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: text !== ""
            width: Math.round(420 * c.s)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: c.errorText !== "" ? c.errorText : c.statusText
            color: c.errorText !== "" ? Qt.lighter(c.lament, 1.5) : Qt.alpha(c.bone, 0.8)
            font.family: c.serif
            font.pixelSize: Math.round(14 * c.s)
            font.italic: c.errorText === "" && c.capsLock
        }
    }

    MouseArea { anchors.fill: parent; z: -1; onPressed: c.refocus() }
}
