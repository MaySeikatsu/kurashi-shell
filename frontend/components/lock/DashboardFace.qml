import QtQuick
import QtQuick.Effects
import Quickshell
import "../../core"

// The dashboard face (W53.5, docs/ux/styles.md §8 "Lock face dashboard"): the console dashboard's void as a lock.
// - The ground is the `ps2` frame's own (frames/Ps2.qml, kind "ground"): the void, the deep blue floor glow, light towers
//   that rise once when the lock appears (at full height at once under reduced motion), motes that stand still. They dim
//   while the daemon is away.
// - A thin clock at the top right (the look's light weight, silver = on_surface) with a soft blue glow, the date under it.
// - The user as a card slot: an original rounded translucent tile (a thin outline, a blue glow line along its foot, the
//   login name's initial inside — never a memory card's silhouette, no console logos) with the name beside it in thin type.
// - The password: an underline field (no box), a thin line with a soft blue glow under it. A wrong password turns the
//   line and the glow to the error role and fades its words in; Caps Lock a thin "CAPS LOCK" in small caps under the line;
//   busy a slow pulse of the glow (only while busy); the retry countdown, PAM's information and its questions (the label
//   over the line), the fingerprint reader, "daemon disconnected": one thin line under it, fading between them.
// Fades of the look's half second on its ease-in-out (`openMs` / `openCurve` when timed), no overshoot; reduced motion:
// cuts. High contrast (`glow` 0): no glow, solid lines. Other outputs (`primary` false): the ground and the clock.
// Colours from roles (rule 4). Ma: the glows are static layers painted once per size and colour; the towers rise once;
// the pulse runs only while busy; the field's caret is a steady line, never blinking.
FaceBase {
    id: c

    readonly property bool busy: lock.busy === true
    readonly property bool waiting: remainingMs > 0
    readonly property bool followUp: (lock.prompt || "") !== ""
    readonly property bool echo: lock.prompt_echo === true
    readonly property string promptText: lock.prompt_key ? I18n.tr(lock.prompt_key)
                                         : (lock.prompt ? lock.prompt : I18n.tr("lockui.dashboard.password"))
    readonly property string errorText: {
        if (lock.message_key === "lock.error.wrong_password") return I18n.tr("lockui.dashboard.wrong")
        if (lock.message_key) return I18n.tr(lock.message_key)
        if (lock.pam_message && lock.pam_message.kind === "error") return lock.pam_message.text || ""
        return ""
    }
    readonly property string statusText: {
        if (!Store.live) return I18n.tr("lockui.disconnected")
        if (busy) return I18n.tr("lockui.checking")
        if (waiting) return I18n.tr("lockui.retry_in").replace("{s}", Math.ceil(remainingMs / 1000))
        if (lock.pam_message && lock.pam_message.kind !== "error" && lock.pam_message.text) return lock.pam_message.text
        if (fingerprint.available === true)
            return I18n.tr(fingerprint.state === "scanning" ? "lockui.fingerprint.scanning" : "lockui.fingerprint.idle")
        return ""
    }
    readonly property string userName: (user && user.name) ? user.name : String(Quickshell.env("USER") || "")
    // The error stays until the next key.
    property bool errorSeen: false
    onErrorTextChanged: errorSeen = errorText === ""
    readonly property bool errorShown: errorText !== "" && !errorSeen
    onFollowUpChanged: { field.text = ""; refocus() }
    onBusyChanged: if (!busy) refocus()

    // ---- look ----------------------------------------------------------------------------------------------------------
    readonly property bool glowOn: Theme.glow > 0
    readonly property int fadeMs: Theme.timed && Theme.springOn ? Theme.openMs : 0
    readonly property color silver: Theme.fg
    readonly property color lineInk: errorShown ? Theme.error : (glowOn ? Qt.alpha(silver, 0.7) : silver)
    readonly property color glowInk: errorShown ? Theme.error : Theme.glowColor
    readonly property string fam: Theme.fam(userName, Theme.families)
    readonly property int thin: 200
    readonly property int light: 300

    color: Theme.color("color.scrim", "#000000")

    function refocus() { field.forceActiveFocus() }
    function submit() {
        if (field.text === "" || busy || waiting) return
        var s = field.text
        field.text = ""
        c.submitted(s)
        s = ""
    }

    component Fade: NumberAnimation {
        duration: c.fadeMs
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.openCurve
    }
    component Tint: ColorAnimation {
        duration: c.fadeMs
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.openCurve
    }
    // A soft static glow round an item's ink (a blurred shadow at the centre), none under high contrast.
    component GlowFx: MultiEffect {
        property color ink: Theme.glowColor
        shadowEnabled: true
        shadowColor: ink
        shadowBlur: 1.0
        blurMax: 32
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 0
        shadowOpacity: Math.min(1, Theme.glow * 2.4)
        autoPaddingEnabled: true
    }

    // ---- the ground: the ps2 frame's (towers rise once) -----------------------------------------------------------------
    Loader {
        id: ground
        anchors.fill: parent
        opacity: Store.live ? 1 : 0.4
        Behavior on opacity { Fade {} }
        Component.onCompleted: setSource(Qt.resolvedUrl("../frames/Ps2.qml"),
                                         { kind: "ground", radius: 0, animate: Theme.springOn })
    }

    // ---- the clock (every output) --------------------------------------------------------------------------------------
    readonly property var dateObj: {
        if (clock.date) return new Date(clock.date + "T12:00:00")
        if (clock.year && clock.month && clock.day) return new Date(clock.year, clock.month - 1, clock.day, 12)
        return null
    }
    Column {
        anchors { right: parent.right; top: parent.top; rightMargin: Math.round(c.width * 0.055); topMargin: Math.round(c.height * 0.06) }
        spacing: 2
        Text {
            anchors.right: parent.right
            text: (c.clock.hh ?? "--") + ":" + (c.clock.mm ?? "--")
            color: c.silver
            font.pixelSize: Math.round(Math.max(56, c.height * 0.088))
            font.weight: c.thin
            font.family: Theme.fam(text, Theme.families)
            font.letterSpacing: 2
            layer.enabled: c.glowOn
            layer.effect: GlowFx {}
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 4
            text: {
                var d = c.dateObj
                if (!d) return String(c.clock.weekday ?? "")
                var loc = Qt.locale((Store.docs["i18n"] || {}).locale || "en")
                return d.toLocaleDateString(loc, I18n.tr("lockui.dashboard.date_format"))
            }
            color: Qt.alpha(c.silver, 0.82)
            font.pixelSize: Math.round(Math.max(16, c.height * 0.02))
            font.weight: c.light
            font.family: Theme.fam(text, Theme.families)
            font.letterSpacing: 1
        }
    }

    // ---- the slot, the name, the field (the focused output) ------------------------------------------------------------
    Item {
        id: panel
        visible: c.primary
        x: Math.round(c.width * 0.16)
        y: Math.round(c.height * 0.38)
        width: Math.round(Math.min(560, c.width * 0.4))
        height: col.height

        Column {
            id: col
            width: parent.width
            spacing: 0

            // The card slot and the user's name.
            Row {
                spacing: 28
                Item {
                    id: slot
                    width: 84; height: 84
                    layer.enabled: c.glowOn
                    layer.effect: GlowFx { shadowOpacity: Math.min(1, Theme.glow * 1.4) }
                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: Qt.alpha(Theme.containerHigh, c.glowOn ? 0.5 : 1)
                        border.width: c.glowOn ? 1 : 2
                        border.color: c.glowOn ? Qt.alpha(c.silver, 0.42) : c.silver
                    }
                    // The inner rim: a second thin rounded line, the tile's depth.
                    Rectangle {
                        visible: c.glowOn
                        anchors { fill: parent; margins: 6 }
                        radius: Theme.nested(16, 6)
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha(c.silver, 0.12)
                    }
                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -3
                        text: c.userName.charAt(0).toUpperCase()
                        color: c.silver
                        font.pixelSize: 38
                        font.weight: c.thin
                        font.family: Theme.fam(text, Theme.families)
                    }
                    // The glow line along its foot.
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 14; rightMargin: 14; bottomMargin: 9 }
                        height: 2
                        radius: 1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.alpha(Theme.glowColor, 0) }
                            GradientStop { position: 0.5; color: c.glowOn ? Theme.glowColor : c.silver }
                            GradientStop { position: 1.0; color: Qt.alpha(Theme.glowColor, 0) }
                        }
                    }
                }
                Text {
                    anchors.verticalCenter: slot.verticalCenter
                    width: panel.width - slot.width - 28
                    elide: Text.ElideRight
                    text: c.userName
                    color: c.silver
                    font.pixelSize: 30
                    font.weight: c.thin
                    font.family: c.fam
                    font.letterSpacing: 1
                }
            }

            Item { width: 1; height: 40 }

            // PAM's question over the line (the password's own label is the placeholder).
            Text {
                width: parent.width
                height: c.followUp ? implicitHeight + 6 : 0
                opacity: c.followUp ? 1 : 0
                Behavior on opacity { Fade {} }
                elide: Text.ElideRight
                text: c.followUp ? c.promptText : ""
                color: Qt.alpha(c.silver, 0.82)
                font.pixelSize: 15
                font.weight: c.light
                font.family: Theme.fam(text, Theme.families)
            }

            // The underline field.
            Item {
                id: fieldBox
                width: parent.width
                height: 44
                opacity: c.busy || c.waiting ? 0.7 : 1
                Behavior on opacity { Fade {} }

                TextInput {
                    id: field
                    anchors { left: parent.left; right: parent.right; bottom: line.top; bottomMargin: 8; leftMargin: 2 }
                    echoMode: c.echo ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    color: c.silver
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.fgOnAccent
                    font.pixelSize: 22
                    font.weight: c.light
                    font.letterSpacing: c.echo ? 1 : 4
                    font.family: Theme.fam(text, Theme.families)
                    clip: true
                    focus: true
                    enabled: c.primary
                    readOnly: c.busy || c.waiting
                    // A steady thin caret (the default one blinks at rest).
                    cursorDelegate: Rectangle {
                        width: 1
                        color: c.silver
                        visible: field.activeFocus && !field.readOnly
                    }
                    Accessible.role: Accessible.EditableText
                    Accessible.name: c.promptText
                    Accessible.passwordEdit: !c.echo
                    onTextChanged: if (text !== "") c.errorSeen = true
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_CapsLock) c.capsKey()
                        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) event.accepted = true
                    }
                    Keys.onReturnPressed: c.submit()
                    Keys.onEnterPressed: c.submit()
                    Keys.onEscapePressed: { text = ""; c.cancelled() }
                    Text {
                        anchors.fill: parent
                        visible: field.text === "" && field.preeditText === ""
                        verticalAlignment: Text.AlignVCenter
                        color: Qt.alpha(c.silver, 0.45)
                        font.pixelSize: 20
                        font.weight: c.light
                        font.family: Theme.fam(text, Theme.families)
                        elide: Text.ElideRight
                        text: c.followUp ? "" : c.promptText
                    }
                }
                // The soft glow under the line: a blurred band of the glow's ink, static; it pulses only while busy.
                Rectangle {
                    id: glowBand
                    visible: c.glowOn
                    anchors { left: parent.left; right: parent.right; verticalCenter: line.verticalCenter; leftMargin: 24; rightMargin: 24 }
                    height: 4
                    radius: 2
                    color: c.glowInk
                    Behavior on color { Tint {} }
                    layer.enabled: c.glowOn
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 1.0
                        blurMax: 40
                        autoPaddingEnabled: true
                    }
                    SequentialAnimation on opacity {
                        id: pulse
                        running: c.busy && c.glowOn && Theme.springOn && c.primary
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 1100; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 1100; easing.type: Easing.InOutSine }
                        onRunningChanged: if (!running) glowBand.opacity = 1
                    }
                }
                Rectangle {
                    id: line
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: c.glowOn ? 1 : 2
                    color: c.lineInk
                    Behavior on color { Tint {} }
                }
            }

            Item { width: 1; height: 10 }

            // Caps Lock: thin small caps under the line.
            Text {
                height: c.capsLock ? implicitHeight + 4 : 0
                opacity: c.capsLock ? 1 : 0
                Behavior on opacity { Fade {} }
                text: I18n.tr("lockui.dashboard.caps")
                color: Qt.alpha(c.silver, 0.85)
                font.pixelSize: 14
                font.weight: c.light
                font.capitalization: Font.SmallCaps
                font.letterSpacing: 2
                font.family: Theme.fam(text, Theme.families)
            }
            // The error: fades in in the error role.
            Text {
                width: parent.width
                height: c.errorShown ? implicitHeight + 4 : 0
                opacity: c.errorShown ? 1 : 0
                Behavior on opacity { Fade {} }
                wrapMode: Text.Wrap
                text: c.errorText
                color: Theme.error
                font.pixelSize: 15
                font.weight: c.light
                font.family: Theme.fam(text, Theme.families)
            }
            // Busy, the countdown, PAM's information, the fingerprint, "daemon disconnected".
            Text {
                width: parent.width
                opacity: c.statusText !== "" ? 1 : 0
                Behavior on opacity { Fade {} }
                wrapMode: Text.Wrap
                text: c.statusText
                color: Qt.alpha(c.silver, 0.72)
                font.pixelSize: 15
                font.weight: c.light
                font.family: Theme.fam(text, Theme.families)
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: c.refocus()
    }
}
