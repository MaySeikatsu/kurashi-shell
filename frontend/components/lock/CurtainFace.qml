import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../core"
import ".."

// The curtain face (W53.3, docs/ux/styles.md §4 "Lock face curtain"): Windows 11's lock in two stages.
// - The curtain: the ground, a big clock (semibold, light on the ground) at the upper third, the date under it, and what
//   plays at the bottom left. Any key or click lifts it: the clock rises and fades on the decelerating curve (Fast Out Slow
//   In, ControlNormalAnimationDuration 250 ms) while the sign-in fades in; reduced motion crossfades.
// - The sign-in: the ground dims under an Acrylic veil, the avatar (a 192 px circle with the login name's letter), the
//   name (Title 28), and the password box — 4 px corners, a 2 px accent line along its bottom while it has the keyboard,
//   the reveal eye and the → submit inside the box. Messages under the box: Caps Lock, the fingerprint, busy, the retry
//   countdown, PAM's information; an error is 11's inline step ("The password is incorrect. Try again." with OK).
// The field has the keyboard from the first frame, curtain or not, so the key that lifts the curtain is the password's
// first character: nothing typed is lost. Back to the curtain after 60 s on the sign-in with an empty box.
// The ground is the look's own (`desk`, a soft original bloom of the accent over it — never a vendor's wallpaper; the
// lock does not know the user's wallpaper yet). Other outputs (`primary` false) keep the curtain. Every colour a palette
// role (rule 4). Ma: painted once per size and colour; the lift is one-shot; the 60 s timer runs only on the sign-in.
FaceBase {
    id: c

    readonly property bool busy: lock.busy === true
    readonly property bool waiting: remainingMs > 0
    readonly property bool followUp: (lock.prompt || "") !== ""
    readonly property bool echo: lock.prompt_echo === true || reveal
    readonly property string promptText: lock.prompt_key ? I18n.tr(lock.prompt_key)
                                         : (lock.prompt ? lock.prompt : I18n.tr("lockui.curtain.password"))
    readonly property string errorText: {
        // A wrong password reads in 11's own words; any other refusal is the daemon's.
        if (lock.message_key === "lock.error.wrong_password") return I18n.tr("lockui.curtain.wrong")
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
    // The curtain is up (the sign-in shows). Only the focused output lifts it.
    property bool lifted: false
    property bool reveal: false
    property bool errorOpen: false
    readonly property bool signIn: lifted && primary
    readonly property int liftMs: Theme.timed ? Theme.openMs : Math.max(0, Theme.quickMs)
    readonly property color ink: "#ffffff"

    color: Theme.color("color.desk", "#0f2a55")

    onErrorTextChanged: if (errorText !== "" && primary) { lifted = true; errorOpen = true; okKey.forceActiveFocus() }
    onFollowUpChanged: { field.text = ""; lifted = true; refocus() }
    onBusyChanged: if (!busy) refocus()
    onSignInChanged: if (!signIn) { reveal = false; field.text = "" }

    function refocus() { if (errorOpen) okKey.forceActiveFocus(); else field.forceActiveFocus() }
    function submit() {
        if (field.text === "" || busy || waiting) return
        var s = field.text
        field.text = ""
        c.submitted(s)
        s = ""
    }
    function dismiss() { errorOpen = false; field.forceActiveFocus() }
    function lift() { if (primary) lifted = true; refocus() }

    // ---- the ground: the desk role with a soft bloom of the accent (static) ------------------------------------------
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(c.color, 1.25) }
            GradientStop { position: 1; color: Qt.darker(c.color, 1.35) }
        }
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: c.width * 0.62; centerY: c.height * 0.72
                centerRadius: Math.max(c.width, c.height) * 0.55
                focalX: centerX; focalY: centerY
                GradientStop { position: 0; color: Qt.alpha(Theme.accent, 0.55) }
                GradientStop { position: 0.45; color: Qt.alpha(Theme.accent, 0.18) }
                GradientStop { position: 1; color: Qt.alpha(Theme.accent, 0) }
            }
            startX: 0; startY: 0
            PathLine { x: c.width; y: 0 }
            PathLine { x: c.width; y: c.height }
            PathLine { x: 0; y: c.height }
            PathLine { x: 0; y: 0 }
        }
    }
    // The sign-in's veil: Acrylic over the ground (a dim scrim; the face cannot blur its own ground).
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha("#000000", 0.42)
        opacity: c.signIn ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: c.liftMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.openCurve } }
    }

    // ---- the curtain: the clock and the date --------------------------------------------------------------------------
    Column {
        id: curtain
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(c.height * 0.16) - (c.signIn && Theme.timed ? c.height * 0.12 : 0)
        opacity: c.signIn ? 0 : 1
        Behavior on y { NumberAnimation { duration: c.liftMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.openCurve } }
        Behavior on opacity { NumberAnimation { duration: c.liftMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.openCurve } }
        spacing: 0
        Text {
            id: time
            anchors.horizontalCenter: parent.horizontalCenter
            text: (c.clock.hh ?? "--") + ":" + (c.clock.mm ?? "--")
            color: c.ink
            // Display (68/92) scaled to the output, as 11 sizes its lock clock: ~134 px at 1080 lines.
            font.pixelSize: Math.round(Math.max(72, c.height * 0.124))
            font.weight: 600
            font.family: Theme.fam(text, Theme.families)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                var d = c.clock.date ? new Date(c.clock.date + "T12:00:00") : null
                return d ? d.toLocaleDateString(Qt.locale((Store.docs["i18n"] || {}).locale || "en"), "dddd, d MMMM")
                         : (c.clock.weekday ?? "")
            }
            color: c.ink
            font.pixelSize: Math.round(Math.max(18, c.height * 0.022))
            font.weight: 500
            font.family: Theme.fam(text, Theme.families)
        }
    }
    // What plays: a small card at the bottom left, on the curtain only (11's media controls on the lock).
    Rectangle {
        visible: c.mediaOn && !c.signIn
        x: 48; y: c.height - height - 96
        width: 300; height: 64
        radius: Theme.rLg
        color: Qt.alpha("#000000", 0.35)
        Column {
            anchors { left: parent.left; leftMargin: 16; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            Text { width: parent.width; elide: Text.ElideRight; color: c.ink; font.pixelSize: Theme.fs; font.weight: 600
                   font.family: Theme.fam(text, Theme.families); text: c.media.title || "" }
            Text { width: parent.width; elide: Text.ElideRight; color: Qt.alpha(c.ink, 0.8); font.pixelSize: Theme.fsLabel
                   font.family: Theme.fam(text, Theme.families); text: c.media.artist || "" }
        }
    }
    // "Daemon disconnected" stands at the bottom on every stage.
    Text {
        visible: !Store.live
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 96 }
        color: c.ink
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("lockui.disconnected")
    }
    MouseArea {
        anchors.fill: parent
        enabled: !c.signIn
        onClicked: c.lift()
    }

    // ---- the sign-in ---------------------------------------------------------------------------------------------------
    Column {
        id: sign
        visible: c.primary
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(c.height * 0.5 - 192 - 24) + (c.signIn || !Theme.timed ? 0 : 24)
        opacity: c.signIn ? 1 : 0
        Behavior on y { NumberAnimation { duration: c.liftMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.openCurve } }
        Behavior on opacity { NumberAnimation { duration: c.liftMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.openCurve } }
        spacing: 0
        width: 296

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 192; height: 192; radius: 96
            color: Theme.color("color.accent_container", "#cce4f7")
            Text {
                anchors.centerIn: parent
                visible: c.userName !== ""
                color: Theme.color("color.on_accent_container", "#003e78")
                font.pixelSize: 80
                font.weight: 400
                font.family: Theme.fam(text, Theme.families)
                text: c.userName.charAt(0).toUpperCase()
            }
            Icon {
                anchors.centerIn: parent
                visible: c.userName === ""
                name: "person"
                glyph: "◡"
                size: 96
                color: Theme.color("color.on_accent_container", "#003e78")
            }
        }
        Item { width: 1; height: 24 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: c.ink
            font.pixelSize: 28
            font.weight: 600
            font.family: Theme.fam(text, Theme.families)
            text: c.userName
        }
        Item { width: 1; height: 24 }

        // The password box (or the error's inline step in its place).
        Item {
            width: parent.width
            height: 32
            Rectangle {
                id: box
                visible: !c.errorOpen
                anchors.fill: parent
                radius: Theme.rSm
                color: field.activeFocus ? Theme.color("color.surface_container_lowest", "#ffffff")
                                         : Qt.alpha(Theme.color("color.surface_container_lowest", "#ffffff"), 0.82)
                border.width: 1
                border.color: Qt.alpha(Theme.fg, 0.1)
                opacity: c.busy || c.waiting ? 0.6 : 1
                // The focused box's 2 px accent line along its bottom, inside the corners.
                Rectangle {
                    visible: field.activeFocus
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 1; rightMargin: 1 }
                    height: 2
                    bottomLeftRadius: Theme.rSm
                    bottomRightRadius: Theme.rSm
                    color: Theme.accent
                }
                TextInput {
                    id: field
                    anchors { left: parent.left; leftMargin: 11; right: keys.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: c.echo ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "●"
                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.fgOnAccent
                    font.pixelSize: 14
                    font.family: Theme.fam(text, Theme.families)
                    clip: true
                    focus: true
                    readOnly: c.busy || c.waiting
                    Accessible.role: Accessible.EditableText
                    Accessible.name: c.promptText
                    Accessible.passwordEdit: !c.echo
                    // The curtain lifts on the first key, and a printable one is the password's first character.
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_CapsLock) c.capsKey()
                        if (!c.lifted) {
                            c.lift()
                            if (event.text === "" || event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                                || event.key === Qt.Key_Escape || event.key === Qt.Key_Space)
                                event.accepted = true
                        }
                    }
                    Keys.onReturnPressed: c.submit()
                    Keys.onEnterPressed: c.submit()
                    Keys.onEscapePressed: { if (text !== "") text = ""; else c.lifted = false }
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: field.text === "" && field.preeditText === ""
                        color: Theme.dim
                        font: field.font
                        elide: Text.ElideRight
                        text: c.promptText
                    }
                }
                Row {
                    id: keys
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    // The reveal eye: shows the password while held (11), a toggle by keyboard.
                    InBoxKey {
                        visible: field.text !== "" && lock.prompt_echo !== true
                        icon: c.reveal ? "visibility_off" : "visibility"
                        glyph: "◉"
                        a11y: I18n.tr("lockui.curtain.reveal")
                        onActivated: { c.reveal = !c.reveal; field.forceActiveFocus() }
                    }
                    InBoxKey {
                        icon: "arrow_forward"
                        glyph: "→"
                        a11y: I18n.tr("lockui.curtain.submit")
                        onActivated: c.submit()
                    }
                }
            }
            // The error's inline step: the message over an OK button, in the box's place.
            Column {
                visible: c.errorOpen
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 296
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: c.ink
                    font.pixelSize: 14
                    font.family: Theme.fam(text, Theme.families)
                    text: c.errorText !== "" ? c.errorText : I18n.tr("lockui.curtain.wrong")
                }
                Rectangle {
                    id: okKey
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 120; height: 32
                    radius: Theme.rSm
                    color: okHit.pressed ? Qt.darker(Qt.alpha("#ffffff", 0.2), 1.0) : Qt.alpha("#ffffff", okHit.containsMouse ? 0.3 : 0.22)
                    border.width: 1
                    border.color: Qt.alpha("#ffffff", 0.18)
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.tr("lockui.curtain.ok")
                    Accessible.onPressAction: c.dismiss()
                    Keys.onPressed: event => {
                        if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space, Qt.Key_Escape].indexOf(event.key) >= 0) {
                            c.dismiss(); event.accepted = true
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        color: c.ink
                        font.pixelSize: 14
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("lockui.curtain.ok")
                    }
                    FocusRing { anchors.fill: parent; shown: okKey.activeFocus; corner: Theme.rSm; stroke: c.ink }
                    MouseArea { id: okHit; anchors.fill: parent; hoverEnabled: true; onClicked: c.dismiss() }
                }
            }
        }
        Item { width: 1; height: 12 }
        // Caps Lock, then the status line (busy, countdown, PAM's information, the fingerprint).
        Text {
            visible: c.capsLock && !c.errorOpen
            anchors.horizontalCenter: parent.horizontalCenter
            color: c.ink
            font.pixelSize: 12
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("lockui.caps_lock")
        }
        Text {
            visible: c.statusText !== "" && !c.errorOpen
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: c.ink
            font.pixelSize: 12
            font.family: Theme.fam(text, Theme.families)
            text: c.statusText
        }
    }

    // A small key inside the password box: 24 × 24, a subtle plate under the pointer.
    component InBoxKey: Rectangle {
        id: k
        property string icon: ""
        property string glyph: ""
        property string a11y: ""
        signal activated()
        width: 28; height: 24
        radius: Theme.rSm
        color: kHit.pressed ? Qt.alpha(Theme.fg, 0.08) : (kHit.containsMouse ? Qt.alpha(Theme.fg, 0.05) : "transparent")
        Accessible.role: Accessible.Button
        Accessible.name: a11y
        Accessible.onPressAction: activated()
        Icon {
            anchors.centerIn: parent
            name: k.icon
            glyph: k.glyph
            size: 16
            color: Theme.dim
        }
        MouseArea { id: kHit; anchors.fill: parent; hoverEnabled: true; onClicked: k.activated() }
    }

    // Back to the curtain after a minute on the sign-in with nothing typed (11's own timeout).
    Timer {
        id: back
        interval: 60000
        running: c.signIn && field.text === "" && !c.busy && !c.errorOpen
        onTriggered: c.lifted = false
    }
}
