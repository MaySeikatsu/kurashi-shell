import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../core"
import ".."

// The Sonoma face (W53.4, docs/ux/styles.md §6 "Lock face sonoma"): macOS 14's lock screen. The date over a huge time at
// the top centre (SF Pro Display semibold → Inter, the look's family, white with a soft shadow), and at the bottom
// centre the user's round picture, the name and a capsule password field ("Enter Password") in frosted white. The
// ground stands in for the blurred wallpaper (the session lock is opaque and the shell does not own the wallpaper): an
// original soft gradient of `desk` with two out-of-focus glows — static, painted once; never Apple's Sonoma art. The hint
// "Touch ID or Enter Password" analogue (the fingerprint line) shows only when the daemon says a reader is enrolled.
// States: a wrong password shakes the field (one-shot, none under reduce motion) with the message under it; Caps Lock
// puts ⇪ inside the field's end; busy, the countdown and PAM's information a line under the field; a PAM question
// relabels the cue (echo when it asks); "daemon disconnected" under the time. The other outputs show the ground, the date
// and the time (`primary` false). Colours from roles (rule 4); Ma: one paint per size and colour, the shake one-shot.
FaceBase {
    id: c

    readonly property real s: Math.max(1, Math.min(width / 1440, height / 900))
    readonly property bool busy: lock.busy === true
    readonly property bool waiting: remainingMs > 0
    readonly property bool followUp: (lock.prompt || "") !== ""
    readonly property bool echo: lock.prompt_echo === true
    readonly property string cue: lock.prompt_key ? I18n.tr(lock.prompt_key)
                                  : (lock.prompt ? lock.prompt : I18n.tr("lockui.sonoma.prompt"))
    readonly property string errorText: {
        if (lock.message_key) return I18n.tr(lock.message_key)
        if (lock.pam_message && lock.pam_message.kind === "error") return lock.pam_message.text || ""
        return ""
    }
    readonly property string statusText: {
        if (busy) return I18n.tr("lockui.checking")
        if (waiting) return I18n.tr("lockui.retry_in").replace("{s}", Math.ceil(remainingMs / 1000))
        if (lock.pam_message && lock.pam_message.kind !== "error" && lock.pam_message.text) return lock.pam_message.text
        if (fingerprint.available === true)
            return I18n.tr(fingerprint.state === "scanning" ? "lockui.fingerprint.scanning" : "lockui.fingerprint.idle")
        return ""
    }
    readonly property string userName: (user && user.name) ? user.name : String(Quickshell.env("USER") || "")
    readonly property string fam: Theme.fam(userName, Theme.families)
    readonly property color ground: Theme.color("color.desk", "#4b5fae")
    readonly property color glowA: Theme.color("color.secondary", "#8944ab")
    readonly property color glowB: Theme.accent
    readonly property color white: Qt.rgba(1, 1, 1, 1)
    readonly property bool moves: Theme.motionKind !== "none"

    color: ground

    onFollowUpChanged: { input.text = ""; refocus() }
    onBusyChanged: if (!busy) refocus()
    onErrorTextChanged: if (errorText !== "" && c.visible && c.moves) shake.restart()
    function refocus() { input.forceActiveFocus() }
    function submit() {
        if (input.text === "" || c.busy || c.waiting) return
        var t = input.text
        input.text = ""             // clear before anything else can observe it
        c.submitted(t)
        t = ""
    }
    function cancel() { input.text = ""; c.cancelled(); input.forceActiveFocus() }

    // ---- the ground: the desk colour, deeper below, two out-of-focus glows (static) ----------------------------------
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(c.ground, 1.18) }
            GradientStop { position: 0.6; color: c.ground }
            GradientStop { position: 1; color: Qt.darker(c.ground, 1.6) }
        }
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: c.width * 0.22; centerY: c.height * 0.78
                focalX: centerX; focalY: centerY
                centerRadius: c.height * 0.6
                GradientStop { position: 0; color: Qt.alpha(c.glowA, 0.55) }
                GradientStop { position: 1; color: Qt.alpha(c.glowA, 0) }
            }
            startX: 0; startY: 0
            PathLine { x: c.width; y: 0 }
            PathLine { x: c.width; y: c.height }
            PathLine { x: 0; y: c.height }
            PathLine { x: 0; y: 0 }
        }
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: c.width * 0.8; centerY: c.height * 0.3
                focalX: centerX; focalY: centerY
                centerRadius: c.height * 0.55
                GradientStop { position: 0; color: Qt.alpha(Qt.lighter(c.glowB, 1.3), 0.45) }
                GradientStop { position: 1; color: Qt.alpha(c.glowB, 0) }
            }
            startX: 0; startY: 0
            PathLine { x: c.width; y: 0 }
            PathLine { x: c.width; y: c.height }
            PathLine { x: 0; y: c.height }
            PathLine { x: 0; y: 0 }
        }
    }

    // ---- the date over the time, top centre (every output) ----------------------------------------------------------
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.075)
        spacing: Math.round(2 * c.s)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                var d = c.clock.date ? new Date(c.clock.date + "T12:00:00") : null
                return d ? d.toLocaleDateString(Qt.locale((Store.docs["i18n"] || {}).locale || "en"), "dddd d MMMM") : (c.clock.weekday ?? "")
            }
            color: Qt.alpha(c.white, 0.92)
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.12)
            font.family: c.fam
            font.pixelSize: Math.round(24 * c.s)
            font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (c.clock.hh ?? "--") + ":" + (c.clock.mm ?? "--")
            color: Qt.alpha(c.white, 0.94)
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.12)
            font.family: c.fam
            font.pixelSize: Math.round(112 * c.s)
            font.weight: Font.DemiBold
            font.letterSpacing: -2 * c.s
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !Store.live
            text: I18n.tr("lockui.disconnected")
            color: c.white
            font.family: c.fam
            font.pixelSize: Math.round(13 * c.s)
        }
    }

    // ---- the user and the field, bottom centre (the focused output) --------------------------------------------------
    Column {
        id: who
        visible: c.primary
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height - height - Math.max(72, 90 * c.s))
        spacing: Math.round(10 * c.s)
        Rectangle {
            id: pic
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(64 * c.s)
            height: width
            radius: width / 2
            clip: true
            color: Qt.alpha(c.white, 0.3)
            Text {
                anchors.centerIn: parent
                visible: img.status !== Image.Ready
                text: c.userName.charAt(0).toUpperCase()
                color: c.white
                font.family: c.fam
                font.pixelSize: Math.round(28 * c.s)
                font.weight: Font.Medium
            }
            Image {
                id: img
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize.width: width
                sourceSize.height: height
                source: (c.user && c.user.avatar) ? c.user.avatar
                    : (Quickshell.env("HOME") ? "file://" + Quickshell.env("HOME") + "/.face" : "")
                layer.enabled: status === Image.Ready
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: c.userName
            color: c.white
            font.family: c.fam
            font.pixelSize: Math.round(14 * c.s)
            font.weight: Font.DemiBold
        }
        // The capsule field.
        Item {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(180 * c.s)
            height: Math.round(30 * c.s)
            property real shakeX: 0
            transform: Translate { x: field.shakeX }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: field; property: "shakeX"; to: -12 * c.s; duration: 50 }
                NumberAnimation { target: field; property: "shakeX"; to: 12 * c.s; duration: 80 }
                NumberAnimation { target: field; property: "shakeX"; to: -8 * c.s; duration: 70 }
                NumberAnimation { target: field; property: "shakeX"; to: 6 * c.s; duration: 60 }
                NumberAnimation { target: field; property: "shakeX"; to: 0; duration: 50 }
            }
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.alpha(c.white, input.activeFocus ? 0.3 : 0.22)
                border.width: 1
                border.color: Qt.alpha(c.white, 0.35)
                opacity: c.busy ? 0.7 : 1
            }
            Text {
                anchors { left: parent.left; leftMargin: Math.round(14 * c.s); verticalCenter: parent.verticalCenter }
                visible: input.text === "" && input.preeditText === ""
                text: c.cue
                color: Qt.alpha(c.white, 0.7)
                font.family: c.fam
                font.pixelSize: Math.round(13 * c.s)
            }
            TextInput {
                id: input
                anchors { fill: parent; leftMargin: Math.round(14 * c.s); rightMargin: Math.round(caps.visible ? 28 * c.s : 14 * c.s) }
                verticalAlignment: TextInput.AlignVCenter
                echoMode: c.echo ? TextInput.Normal : TextInput.Password
                passwordCharacter: "•"
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                readOnly: c.busy || c.waiting
                color: c.white
                selectionColor: Qt.alpha(c.white, 0.4)
                selectedTextColor: c.white
                font.family: c.fam
                font.pixelSize: Math.round(14 * c.s)
                font.letterSpacing: c.echo ? 0 : 2
                clip: true
                focus: true
                activeFocusOnTab: true
                cursorVisible: activeFocus && !readOnly
                Accessible.name: c.cue
                onAccepted: c.submit()
                Keys.onEscapePressed: c.cancel()
                Keys.onPressed: event => { if (event.key === Qt.Key_CapsLock) c.capsKey() }
            }
            Text {
                id: caps
                visible: c.capsLock
                anchors { right: parent.right; rightMargin: Math.round(12 * c.s); verticalCenter: parent.verticalCenter }
                text: "⇪"
                color: c.white
                font.family: c.fam
                font.pixelSize: Math.round(15 * c.s)
                Accessible.name: I18n.tr("lockui.caps_lock")
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: text !== ""
            width: Math.round(300 * c.s)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: c.errorText !== "" ? c.errorText : c.statusText
            color: Qt.alpha(c.white, 0.9)
            font.family: c.fam
            font.pixelSize: Math.round(12 * c.s)
        }
    }

    MouseArea { anchors.fill: parent; z: -1; onPressed: c.refocus() }
}
