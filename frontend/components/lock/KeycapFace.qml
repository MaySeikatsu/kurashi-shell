import QtQuick
import Quickshell
import "../../core"
import ".."

// The keycap face (W53.7, docs/ux/styles.md §9 sekai, K42): SekaiPop's lock as a keyboard. The dot field of the plain face
// (dots that grow toward the top-right and bottom-left corners, painted once per size), the time on four keys (KeyClock:
// a changed digit drops in once a minute), the date on a wide key under it, the user on a key with their initial, and
// the password as one long key with an Enter key at its end — the Enter key submits (a click or Return) and sits pressed
// onto its shadow while PAM checks. States: a wrong password shakes the long key on the look's spring (one-shot; none
// under reduce motion) and a red key under it says why; Caps Lock lights a ⇪ key beside the field (pressed down, as a
// latched key, only while on: never an inert key); the countdown, PAM's information and the fingerprint on a small key
// under the field; what plays on the last key; "daemon disconnected" at the foot. The other outputs show the field of
// dots, the time and the date (`primary` false). Every block is a Block in the keycap chrome (ink outline, ring, hard
// shadow), colours from roles (rule 4); Ma: painted once, motion one-shot.
FaceBase {
    id: c

    readonly property real s: Math.max(0.8, Math.min(width / 1920, height / 1080))
    readonly property bool busy: lock.busy === true
    readonly property bool waiting: remainingMs > 0
    readonly property bool followUp: (lock.prompt || "") !== ""
    readonly property bool echo: lock.prompt_echo === true
    readonly property string cue: lock.prompt_key ? I18n.tr(lock.prompt_key)
                                  : (lock.prompt ? lock.prompt : I18n.tr("lockui.prompt.password"))
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
    readonly property bool mediaOn: !!(media.title || media.artist)
    function fam(t) { return Theme.fam(t, Theme.families) }

    color: Theme.surface

    onFollowUpChanged: { input.text = ""; refocus() }
    onBusyChanged: if (!busy) refocus()
    onErrorTextChanged: if (errorText !== "" && c.visible && Theme.springOn) shake.restart()
    function refocus() { input.forceActiveFocus() }
    function submit() {
        if (input.text === "" || c.busy || c.waiting) return
        var t = input.text
        input.text = ""             // clear before anything else can observe it
        c.submitted(t)
        t = ""
    }

    // ---- the dot field (the plain face's, K42) --------------------------------------------------------------------------
    Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        readonly property string paintKey: [Theme.line, Theme.ringW].join("|")
        onPaintKeyChanged: requestPaint()
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
    Loader {
        anchors.fill: parent
        active: Theme.texShell
        sourceComponent: Relief { anchors.fill: parent }
    }

    Column {
        id: col
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.26)
        spacing: Math.round(18 * c.s)

        KeyClock {
            anchors.horizontalCenter: parent.horizontalCenter
            hh: c.clock.hh ?? "--"
            mm: c.clock.mm ?? "--"
            keyW: Math.round(104 * c.s)
            keyH: Math.round(140 * c.s)
            digitSize: Math.round(100 * c.s)
            animate: c.visible
        }
        // The date on a wide key.
        Block {
            anchors.horizontalCenter: parent.horizontalCenter
            width: dateText.implicitWidth + Math.round(40 * c.s)
            height: Math.round(44 * c.s) + Theme.shadowDy
            radius: Theme.rFull
            fill: Theme.ring
            animate: false
            penSeed: 0x5E70
            Text {
                id: dateText
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -Theme.shadowDy / 2
                text: {
                    var d = c.clock.date ? new Date(c.clock.date + "T12:00:00") : null
                    return d ? d.toLocaleDateString(Qt.locale((Store.docs["i18n"] || {}).locale || "en"),
                                                     I18n.tr("lockui.keycap.date_format"))
                             : (c.clock.weekday ?? "")
                }
                color: Theme.fg
                font.family: c.fam(text)
                font.pixelSize: Math.round(20 * c.s)
                font.weight: Theme.wBold
            }
        }
        Item { width: 1; height: Math.round(18 * c.s) }

        // ---- the user and the field (the focused output) ------------------------------------------------------------
        Row {
            visible: c.primary
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(12 * c.s)
            // The user: a key with the initial on a tonal disc and the name.
            Block {
                width: nameRow.implicitWidth + Math.round(28 * c.s)
                height: Math.round(56 * c.s) + Theme.shadowDy
                radius: Theme.rFull
                fill: Theme.containerHigh
                animate: false
                penSeed: 0x5E71
                Row {
                    id: nameRow
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -Theme.shadowDy / 2
                    spacing: Math.round(10 * c.s)
                    Rectangle {
                        width: Math.round(34 * c.s)
                        height: width
                        radius: width / 2
                        color: Theme.accent
                        border.width: Math.max(1, Theme.outlineW - 1)
                        border.color: Theme.line
                        Text {
                            anchors.centerIn: parent
                            text: c.userName.charAt(0).toUpperCase()
                            color: Theme.fgOnAccent
                            font.family: c.fam(text)
                            font.pixelSize: Math.round(18 * c.s)
                            font.weight: Font.Black
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: c.userName
                        color: Theme.fg
                        font.family: c.fam(text)
                        font.pixelSize: Math.round(18 * c.s)
                        font.weight: Theme.wBold
                    }
                }
            }
            // Caps Lock: a latched key, lit, only while on.
            Block {
                visible: c.capsLock
                width: capsText.implicitWidth + Math.round(28 * c.s)
                height: Math.round(56 * c.s) + Theme.shadowDy
                radius: Theme.rLg
                fill: Theme.warning
                pressed: true
                animate: false
                penSeed: 0x5E72
                Text {
                    id: capsText
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -Theme.shadowDy / 2 + (Theme.sinkY > 0 ? Theme.sinkY / 2 : 0)
                    text: "⇪ " + I18n.tr("lockui.keycap.caps")
                    color: Theme.color("color.on_warning", Theme.fg)
                    font.family: c.fam(text)
                    font.pixelSize: Math.round(16 * c.s)
                    font.weight: Font.Black
                }
                Accessible.role: Accessible.StaticText
                Accessible.name: I18n.tr("lockui.caps_lock")
            }
            // The long key: the password.
            Item {
                id: field
                width: Math.round(380 * c.s)
                height: Math.round(56 * c.s) + Theme.shadowDy
                property real shakeX: 0
                transform: Translate { x: field.shakeX }
                SequentialAnimation {
                    id: shake
                    NumberAnimation { target: field; property: "shakeX"; to: -14 * c.s; duration: 60; easing.type: Easing.OutQuad }
                    NumberAnimation { target: field; property: "shakeX"; to: 12 * c.s; duration: 90; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: field; property: "shakeX"; to: -6 * c.s; duration: 80; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: field; property: "shakeX"; to: 0; duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot }
                }
                Block {
                    anchors.fill: parent
                    radius: Theme.rFull
                    fill: c.errorText !== "" ? Qt.tint(Theme.containerHigh, Qt.alpha(Theme.error, 0.18)) : Theme.containerHigh
                    animate: false
                    opacity: c.busy ? 0.7 : 1
                    penSeed: 0x5E73
                    Text {
                        anchors { left: parent.left; leftMargin: Math.round(24 * c.s); verticalCenter: parent.verticalCenter; verticalCenterOffset: -Theme.shadowDy / 2 }
                        visible: input.text === "" && input.preeditText === ""
                        text: c.cue
                        color: Theme.dim
                        font.family: c.fam(text)
                        font.pixelSize: Math.round(17 * c.s)
                    }
                    TextInput {
                        id: input
                        anchors { fill: parent; leftMargin: Math.round(24 * c.s); rightMargin: Math.round(24 * c.s); bottomMargin: Theme.shadowDy }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: c.echo ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "●"
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        readOnly: c.busy || c.waiting
                        color: Theme.fg
                        selectionColor: Theme.accent
                        font.family: Theme.families[0]
                        font.pixelSize: Math.round(18 * c.s)
                        font.letterSpacing: c.echo ? 0 : 3 * c.s
                        clip: true
                        focus: true
                        activeFocusOnTab: true
                        cursorVisible: activeFocus && !readOnly
                        Accessible.name: c.cue
                        onAccepted: c.submit()
                        Keys.onEscapePressed: { input.text = ""; c.cancelled() }
                        Keys.onPressed: event => { if (event.key === Qt.Key_CapsLock) c.capsKey() }
                    }
                }
            }
            // Enter: a key that submits; down while PAM checks.
            Block {
                id: enter
                width: Math.round(76 * c.s)
                height: Math.round(56 * c.s) + Theme.shadowDy
                radius: Theme.rLg
                fill: Theme.accent
                pressed: c.busy || enterTap.pressed
                penSeed: 0x5E74
                Icon {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -Theme.shadowDy / 2 + (enter.pressed && Theme.sinkY > 0 ? Theme.sinkY / 2 : 0)
                    name: "keyboard_return"
                    glyph: "↵"
                    color: Theme.fgOnAccent
                    size: Math.round(28 * c.s)
                }
                TapHandler { id: enterTap; onTapped: c.submit() }
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("lockui.keycap.enter")
            }
        }

        // Why it failed (a red key), or what is going on (a small key).
        Block {
            visible: c.primary && (c.errorText !== "" || c.statusText !== "")
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(Math.round(620 * c.s), msg.implicitWidth + Math.round(36 * c.s))
            height: msg.height + Math.round(18 * c.s) + Theme.shadowDy
            radius: Theme.rFull
            fill: c.errorText !== "" ? Theme.error : Theme.ring
            animate: false
            penSeed: 0x5E75
            Text {
                id: msg
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -Theme.shadowDy / 2
                width: Math.min(implicitWidth, Math.round(580 * c.s))
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: c.errorText !== "" ? c.errorText : c.statusText
                color: c.errorText !== "" ? Theme.color("color.on_error", "#ffffff") : Theme.fg
                font.family: c.fam(text)
                font.pixelSize: Math.round(16 * c.s)
                font.weight: Theme.wBold
            }
        }
        Text {
            visible: c.mediaOn
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(560 * c.s)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: "♪ " + (c.media.title ?? "") + (c.media.artist ? " — " + c.media.artist : "")
            color: Theme.dim
            font.family: c.fam(text)
            font.pixelSize: Math.round(15 * c.s)
        }
    }

    Text {
        visible: !Store.live
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 88 }
        text: I18n.tr("lockui.disconnected")
        color: Theme.error
        font.family: c.fam(text)
        font.pixelSize: Math.round(15 * c.s)
        font.weight: Theme.wBold
    }

    MouseArea { anchors.fill: parent; z: -1; onPressed: c.refocus() }
}
