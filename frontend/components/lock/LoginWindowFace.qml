import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import "../../core"
import ".."
import "../decor"

// The login window face (W53.4, docs/ux/styles.md §5 "Lock face login-window"): Mac OS X 10.2–10.4's login window. An
// original Aqua blue ground (`desk`, deeper at the edges, two soft swells of light — static, painted once; never Apple's
// wallpaper), and in its middle a window without a title bar: a brushed-metal header with our mark in blue gel and the
// host name (never Apple's logo or "Mac OS X"), a hairline, then the pinstriped body — the user's picture and name, the
// **Password** field with the blue focus halo, and the **Log In** button in the look's button part (Aqua's gel: as the
// default button it pulses three times, then rests). Shown at once (a keyboard-first lock). Widgets keep 10.x's
// 1024 × 768 proportions (`s`).
// States (10.x's own behaviour where it had one): a wrong password shakes the window side to side (one-shot, none under
// reduce motion) and says why in red under the field; Caps Lock puts ⇪ at the field's end; busy, the countdown, PAM's
// information and the fingerprint reader a line under the field; a PAM question relabels it (echo when it asks);
// "daemon disconnected", the clock and the date low in the middle. The other outputs show the ground and the clock
// (`primary` false). Colours from roles (rule 4); Ma: one paint per size and colour, the pulse and the shake one-shot.
FaceBase {
    id: c

    readonly property real s: Math.max(1, Math.min(width / 1024, height / 768))
    readonly property bool busy: lock.busy === true
    readonly property bool waiting: remainingMs > 0
    readonly property bool followUp: (lock.prompt || "") !== ""
    readonly property bool echo: lock.prompt_echo === true
    readonly property string cue: lock.prompt_key ? I18n.tr(lock.prompt_key)
                                  : (lock.prompt ? lock.prompt : I18n.tr("lockui.login_window.password"))
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
    readonly property string host: String(Quickshell.env("HOSTNAME") || "") || "暮らし"
    readonly property string fam: Theme.fam(userName, Theme.families)

    readonly property color ground: Theme.color("color.desk", "#2e6cc0")
    readonly property color face: Theme.color("color.surface_container", "#ededed")
    readonly property color ink: Theme.color("color.on_surface", "#000000")
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

    // ---- the ground: Aqua blue, deeper at the edges, two soft swells of light (an original pattern; static) ----------
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.darker(c.ground, 1.3) }
            GradientStop { position: 0.5; color: Qt.lighter(c.ground, 1.12) }
            GradientStop { position: 1; color: Qt.darker(c.ground, 1.45) }
        }
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: 0; y1: c.height * 0.3; x2: 0; y2: c.height * 0.75
                GradientStop { position: 0; color: Qt.alpha(c.white, 0.16) }
                GradientStop { position: 1; color: Qt.alpha(c.white, 0) }
            }
            startX: -c.width * 0.05; startY: c.height * 0.62
            PathCubic { x: c.width * 1.05; y: c.height * 0.3; control1X: c.width * 0.3; control1Y: c.height * 0.28; control2X: c.width * 0.62; control2Y: c.height * 0.52 }
            PathLine { x: c.width * 1.05; y: c.height * 0.48 }
            PathCubic { x: -c.width * 0.05; y: c.height * 0.8; control1X: c.width * 0.65; control1Y: c.height * 0.7; control2X: c.width * 0.32; control2Y: c.height * 0.46 }
        }
        ShapePath {
            strokeColor: Qt.alpha(c.white, 0.18)
            strokeWidth: 2
            fillColor: "transparent"
            startX: -c.width * 0.05; startY: c.height * 0.7
            PathCubic { x: c.width * 1.05; y: c.height * 0.4; control1X: c.width * 0.35; control1Y: c.height * 0.38; control2X: c.width * 0.6; control2Y: c.height * 0.62 }
        }
    }

    // ---- low: the clock, the date, daemon state (every output) ------------------------------------------------------
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.86)
        spacing: Math.round(2 * c.s)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (c.clock.hh ?? "--") + ":" + (c.clock.mm ?? "--")
            color: c.white
            font.family: c.fam
            font.pixelSize: Math.round(18 * c.s)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                var d = c.clock.date ? new Date(c.clock.date + "T12:00:00") : null
                return d ? d.toLocaleDateString(Qt.locale((Store.docs["i18n"] || {}).locale || "en"), "dddd, d MMMM") : (c.clock.weekday ?? "")
            }
            color: Qt.alpha(c.white, 0.85)
            font.family: c.fam
            font.pixelSize: Math.round(11 * c.s)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !Store.live
            text: I18n.tr("lockui.disconnected")
            color: c.white
            font.family: c.fam
            font.pixelSize: Math.round(11 * c.s)
        }
    }

    // ---- the login window (the focused output) ------------------------------------------------------------------------
    Item {
        id: win
        visible: c.primary
        width: Math.round(440 * c.s)
        height: header.height + body.height
        x: Math.round((c.width - width) / 2) + shakeX
        y: Math.round(c.height * 0.44 - height / 2)
        property real shakeX: 0
        SequentialAnimation {
            id: shake
            NumberAnimation { target: win; property: "shakeX"; to: -14 * c.s; duration: 50 }
            NumberAnimation { target: win; property: "shakeX"; to: 14 * c.s; duration: 80 }
            NumberAnimation { target: win; property: "shakeX"; to: -10 * c.s; duration: 70 }
            NumberAnimation { target: win; property: "shakeX"; to: 8 * c.s; duration: 60 }
            NumberAnimation { target: win; property: "shakeX"; to: -4 * c.s; duration: 50 }
            NumberAnimation { target: win; property: "shakeX"; to: 0; duration: 40 }
        }
        RectangularShadow {
            anchors.fill: parent
            radius: Math.round(6 * c.s)
            blur: 26 * c.s
            offset.y: 8 * c.s
            color: Qt.rgba(0, 0, 0, 0.5)
        }
        // The brushed-metal header: our mark in blue gel, the host name.
        Rectangle {
            id: header
            width: parent.width
            height: Math.round(112 * c.s)
            topLeftRadius: Math.round(6 * c.s)
            topRightRadius: Math.round(6 * c.s)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(c.face, 1.04) }
                GradientStop { position: 1; color: Qt.darker(c.face, 1.1) }
            }
            Pattern { anchors.fill: parent; kind: "brushed"; strength: 0.09; radius: 6 * c.s }
            Row {
                anchors.centerIn: parent
                spacing: Math.round(14 * c.s)
                MenuMark {
                    anchors.verticalCenter: parent.verticalCenter
                    size: Math.round(58 * c.s)
                    color: Theme.accent
                    gloss: 0.9
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: c.host
                    color: Qt.darker(c.face, 2.6)
                    font.family: c.fam
                    font.pixelSize: Math.round(30 * c.s)
                    font.weight: Font.Light
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(0, 0, 0, 0.3) }
        }
        // The pinstriped body.
        Rectangle {
            id: body
            y: header.height
            width: parent.width
            height: Math.round(172 * c.s) + (msg.visible ? msg.height + Math.round(6 * c.s) : 0)
            bottomLeftRadius: Math.round(6 * c.s)
            bottomRightRadius: Math.round(6 * c.s)
            color: c.face
            Pattern { anchors.fill: parent; radius: 6 * c.s }
            // The picture and the name.
            Row {
                x: Math.round(28 * c.s)
                y: Math.round(20 * c.s)
                spacing: Math.round(14 * c.s)
                Rectangle {
                    id: pic
                    width: Math.round(56 * c.s)
                    height: width
                    radius: Math.round(4 * c.s)
                    clip: true
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.35)
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(c.ground, 1.6) }
                        GradientStop { position: 1; color: c.ground }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: img.status !== Image.Ready
                        text: c.userName.charAt(0).toUpperCase()
                        color: c.white
                        font.family: c.fam
                        font.pixelSize: Math.round(28 * c.s)
                        font.weight: Font.Bold
                    }
                    Image {
                        id: img
                        anchors.fill: parent
                        anchors.margins: 1
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        sourceSize.width: width
                        sourceSize.height: height
                        source: (c.user && c.user.avatar) ? c.user.avatar
                            : (Quickshell.env("HOME") ? "file://" + Quickshell.env("HOME") + "/.face" : "")
                    }
                }
                Text {
                    anchors.verticalCenter: pic.verticalCenter
                    text: c.userName
                    color: c.ink
                    font.family: c.fam
                    font.pixelSize: Math.round(15 * c.s)
                    font.weight: Font.Bold
                }
            }
            // "Password:" and the field, right-aligned labels as 10.x.
            Row {
                id: fieldRow
                x: Math.round(28 * c.s)
                y: Math.round(90 * c.s)
                spacing: Math.round(8 * c.s)
                Text {
                    width: Math.round(80 * c.s)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                    text: c.cue + (c.cue.endsWith(":") ? "" : ":")
                    color: c.ink
                    font.family: c.fam
                    font.pixelSize: Math.round(13 * c.s)
                }
                Item {
                    width: Math.round(200 * c.s)
                    height: Math.round(22 * c.s)
                    // The halo: Aqua's blue focus ring round the field.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -Math.round(3 * c.s)
                        visible: input.activeFocus
                        radius: Math.round(4 * c.s)
                        color: "transparent"
                        border.width: Math.round(3 * c.s)
                        border.color: Qt.alpha(Theme.accent, 0.55)
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: Theme.color("color.surface_container_lowest", "#ffffff")
                        border.width: 1
                        border.color: Qt.darker(c.face, 1.45)
                        opacity: c.busy ? 0.7 : 1
                        // 10.x's sunken field: a darker top line inside.
                        Rectangle { x: 1; y: 1; width: parent.width - 2; height: 1; color: Qt.rgba(0, 0, 0, 0.12) }
                    }
                    TextInput {
                        id: input
                        anchors { fill: parent; leftMargin: Math.round(5 * c.s); rightMargin: Math.round(caps.visible ? 22 * c.s : 5 * c.s) }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: c.echo ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        readOnly: c.busy || c.waiting
                        color: c.ink
                        selectionColor: Theme.color("color.accent_container", "#b5d5ff")
                        selectedTextColor: c.ink
                        font.family: c.fam
                        font.pixelSize: Math.round(13 * c.s)
                        clip: true
                        focus: true
                        activeFocusOnTab: true
                        cursorVisible: activeFocus && !readOnly
                        Accessible.name: c.cue
                        onAccepted: c.submit()
                        Keys.onEscapePressed: c.cancel()
                        Keys.onPressed: event => { if (event.key === Qt.Key_CapsLock) c.capsKey() }
                    }
                    // Caps Lock: ⇪ at the field's end (10.x's own place for it).
                    Text {
                        id: caps
                        visible: c.capsLock
                        anchors { right: parent.right; rightMargin: Math.round(5 * c.s); verticalCenter: parent.verticalCenter }
                        text: "⇪"
                        color: c.ink
                        font.family: c.fam
                        font.pixelSize: Math.round(14 * c.s)
                        Accessible.name: I18n.tr("lockui.caps_lock")
                    }
                }
            }
            // The wrong password, the countdown, PAM's word: one line under the field.
            Text {
                id: msg
                visible: text !== ""
                x: fieldRow.x + Math.round(88 * c.s)
                y: fieldRow.y + fieldRow.height + Math.round(6 * c.s)
                width: Math.round(200 * c.s)
                wrapMode: Text.WordWrap
                text: c.errorText !== "" ? c.errorText : c.statusText
                color: c.errorText !== "" ? Theme.error : Theme.color("color.on_surface_variant", "#4c4c4c")
                font.family: c.fam
                font.pixelSize: Math.round(11 * c.s)
            }
            // Log In: the look's button part (Aqua's gel; the default button pulses, then rests).
            FocusScope {
                id: logIn
                anchors { right: parent.right; bottom: parent.bottom; rightMargin: Math.round(22 * c.s); bottomMargin: Math.round(16 * c.s) }
                width: Math.max(Math.round(84 * c.s), logInText.implicitWidth + Math.round(30 * c.s))
                height: Math.round(22 * c.s)
                opacity: c.busy || c.waiting ? 0.6 : 1
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: logInText.text
                Accessible.onPressAction: c.submit()
                Keys.onPressed: event => {
                    if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].indexOf(event.key) >= 0) { c.submit(); event.accepted = true }
                }
                DecorHost {
                    id: logInFace
                    slot: "button"
                    anchors.fill: parent
                    onLoaded: {
                        item.primary = true
                        item.hovered = Qt.binding(function () { return logInHit.containsMouse })
                        item.pressed = Qt.binding(function () { return logInHit.pressed })
                    }
                }
                Rectangle {
                    visible: !logInFace.has
                    anchors.fill: parent
                    radius: height / 2
                    color: Theme.accent
                    border.width: 1
                    border.color: Qt.darker(Theme.accent, 1.5)
                }
                Text {
                    id: logInText
                    anchors.centerIn: parent
                    text: I18n.tr("lockui.login_window.log_in")
                    color: logInFace.ready && logInFace.item.ink.a > 0 ? logInFace.item.ink : Theme.fgOnAccent
                    font.family: c.fam
                    font.pixelSize: Math.round(13 * c.s)
                }
                FocusRing { anchors.fill: parent; shown: logIn.activeFocus; corner: height / 2 }
                MouseArea { id: logInHit; anchors.fill: parent; hoverEnabled: true; onClicked: c.submit() }
            }
        }
    }

    MouseArea { anchors.fill: parent; z: -1; onPressed: c.refocus() }
}
