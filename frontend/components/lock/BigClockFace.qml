import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../core"
import ".."

// The big-clock face (W53.8, docs/ux/styles.md "material"): Android 12+'s lock screen in Material You, drawn anew. The
// date at the top left (the "smartspace" line), the large clock — the hours stacked over the minutes, each line at 0.7 of
// the type size apart (AOSP SystemUI customization dimens: large_clock_text_size 150 dp, keyguard_clock_line_spacing_scale
// .7) — in the light tone of the primary, a small padlock above the field, the password as M3's filled-pill field
// ("Enter password") low in the middle, and, when a reader is enrolled, the fingerprint mark at the foot, where Android
// puts its under-display sensor. Roboto Flex at a wide, round width (`wdth` 125) when installed, Roboto otherwise.
// The ground stands in for the dimmed wallpaper (the session lock is opaque): the lowest surface with two tonal washes of
// the palette's containers — static, painted once; never Google's art or the Pixel's clock face.
// States, as M3's text field: a wrong password turns the field's indicator and supporting text the error role and nudges
// the field once (none under reduce motion); Caps Lock the trailing caps icon and its line; busy a circular indicator at
// the field's end (it turns only while PAM checks) and "Checking…"; the countdown, PAM's information and the fingerprint
// hint as the supporting text; a PAM question relabels the field (echo when it asks); "daemon disconnected" under the
// date. Other outputs (`primary` false): the ground, the date and the clock. Roles only (rule 4).
FaceBase {
    id: c

    readonly property real s: Math.max(0.75, Math.min(width / 1440, height / 900))
    readonly property bool busy: lock.busy === true
    readonly property bool waiting: remainingMs > 0
    readonly property bool followUp: (lock.prompt || "") !== ""
    readonly property bool echo: lock.prompt_echo === true
    readonly property string cue: lock.prompt_key ? I18n.tr(lock.prompt_key)
                                  : (lock.prompt ? lock.prompt : I18n.tr("lockui.big-clock.prompt"))
    readonly property string errorText: {
        if (lock.message_key) return lock.message_key === "lock.error.wrong_password" ? I18n.tr("lockui.big-clock.wrong") : I18n.tr(lock.message_key)
        if (lock.pam_message && lock.pam_message.kind === "error") return lock.pam_message.text || ""
        return ""
    }
    readonly property string statusText: {
        if (busy) return I18n.tr("lockui.checking")
        if (waiting) return I18n.tr("lockui.retry_in").replace("{s}", Math.ceil(remainingMs / 1000))
        if (lock.pam_message && lock.pam_message.kind !== "error" && lock.pam_message.text) return lock.pam_message.text
        if (capsLock) return I18n.tr("lockui.caps_lock")
        if (fingerprint.available === true)
            return I18n.tr(fingerprint.state === "scanning" ? "lockui.fingerprint.scanning" : "lockui.fingerprint.idle")
        return ""
    }
    readonly property bool hasError: errorText !== ""
    readonly property string userName: (user && user.name) ? user.name : String(Quickshell.env("USER") || "")
    readonly property var fams: Theme.families
    readonly property color ink: Theme.fg
    readonly property color variant: Theme.color("color.on_surface_variant", Theme.dim)
    // The clock's tone: Material You's light primary on a dark ground, the deep one on a light ground — the accent role.
    readonly property color clockInk: Theme.accent
    readonly property bool moves: Theme.motionKind !== "none"

    color: Theme.color("color.surface_container_lowest", "#0f0d13")

    onFollowUpChanged: { input.text = ""; refocus() }
    onBusyChanged: if (!busy) refocus()
    onErrorTextChanged: if (errorText !== "" && c.visible && c.moves) nudge.restart()
    function refocus() { input.forceActiveFocus() }
    function submit() {
        if (input.text === "" || c.busy || c.waiting) return
        var t = input.text
        input.text = ""             // clear before anything else can observe it
        c.submitted(t)
        t = ""
    }
    function cancel() { input.text = ""; c.cancelled(); input.forceActiveFocus() }

    // ---- the ground: two tonal washes over the lowest surface (static) -----------------------------------------------
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: c.width * 0.85; centerY: c.height * 0.05
                focalX: centerX; focalY: centerY
                centerRadius: c.height * 0.9
                GradientStop { position: 0; color: Qt.alpha(Theme.color("color.accent_container", "#4f378b"), 0.55) }
                GradientStop { position: 1; color: Qt.alpha(Theme.color("color.accent_container", "#4f378b"), 0) }
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
                centerX: c.width * 0.1; centerY: c.height * 1.0
                focalX: centerX; focalY: centerY
                centerRadius: c.height * 0.8
                GradientStop { position: 0; color: Qt.alpha(Theme.selected, 0.6) }
                GradientStop { position: 1; color: Qt.alpha(Theme.selected, 0) }
            }
            startX: 0; startY: 0
            PathLine { x: c.width; y: 0 }
            PathLine { x: c.width; y: c.height }
            PathLine { x: 0; y: c.height }
            PathLine { x: 0; y: 0 }
        }
    }

    // ---- the date line, top left (every output) ----------------------------------------------------------------------
    Column {
        x: Math.round(40 * c.s)
        y: Math.round(36 * c.s)
        spacing: Math.round(4 * c.s)
        Text {
            text: {
                var d = c.clock.date ? new Date(c.clock.date + "T12:00:00") : null
                return d ? d.toLocaleDateString(Qt.locale((Store.docs["i18n"] || {}).locale || "en"),
                                                I18n.tr("lockui.big-clock.date_format"))
                         : (c.clock.weekday ?? "")
            }
            color: c.ink
            font.family: Theme.fam(text, c.fams)
            font.pixelSize: Math.round(20 * c.s)
            font.weight: Font.Normal
        }
        Text {
            visible: !Store.live
            text: I18n.tr("lockui.disconnected")
            color: Theme.error
            font.family: Theme.fam(text, c.fams)
            font.pixelSize: Math.round(14 * c.s)
        }
    }

    // ---- the large clock: hours over minutes, the lines 0.7 of the type size apart (every output) --------------------
    Column {
        id: big
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.12)
        readonly property real px: Math.round(200 * c.s)
        spacing: 0
        Repeater {
            model: [c.clock.hh ?? "--", c.clock.mm ?? "--"]
            Text {
                required property string modelData
                anchors.horizontalCenter: parent.horizontalCenter
                height: Math.round(big.px * 0.7) + (big.px * 0.1)
                verticalAlignment: Text.AlignVCenter
                text: modelData
                color: c.clockInk
                font.family: Theme.fam("0", c.fams)
                font.pixelSize: big.px
                font.weight: Font.Medium
                // Roboto Flex's wide cut for the clock's round digits (ignored by a font without the axis).
                font.variableAxes: ({ "wdth": 125, "wght": 500 })
                font.letterSpacing: -2 * c.s
                font.features: ({ "tnum": 1 })
                Accessible.ignored: true
            }
        }
        Accessible.role: Accessible.StaticText
        Accessible.name: (c.clock.hh ?? "") + ":" + (c.clock.mm ?? "")
    }

    // ---- the padlock, the field and its supporting line (the focused output) ----------------------------------------
    Column {
        id: who
        visible: c.primary
        anchors.horizontalCenter: parent.horizontalCenter
        // A fixed top (the supporting line grows below the field, never moves it), clear of the greeter's 72 px strip.
        y: Math.round(Math.min(parent.height * 0.66, parent.height - 72 - 160 * c.s))
        spacing: Math.round(14 * c.s)
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "lock"
            glyph: "🔒"
            filled: true
            size: Math.round(24 * c.s)
            color: c.hasError ? Theme.error : c.ink
        }
        // M3's filled text field as Android's bouncer draws its password: a full-round container in the high surface,
        // the hint inside, the error role round it on a wrong password.
        Item {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(320 * c.s)
            height: Math.round(56 * c.s)
            property real nudgeX: 0
            transform: Translate { x: field.nudgeX }
            SequentialAnimation {
                id: nudge
                NumberAnimation { target: field; property: "nudgeX"; to: -10 * c.s; duration: 60; easing.type: Easing.OutCubic }
                NumberAnimation { target: field; property: "nudgeX"; to: 8 * c.s; duration: 90; easing.type: Easing.InOutCubic }
                NumberAnimation { target: field; property: "nudgeX"; to: 0; duration: 150; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1, 1] }
            }
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Theme.color("color.surface_container_high", "#2b2930")
                border.width: c.hasError ? 2 : (input.activeFocus ? 2 : 0)
                border.color: c.hasError ? Theme.error : Theme.accent
                opacity: c.busy ? 0.7 : 1
            }
            Text {
                anchors { left: parent.left; leftMargin: Math.round(24 * c.s); verticalCenter: parent.verticalCenter }
                visible: input.text === "" && input.preeditText === ""
                text: c.cue
                color: c.variant
                font.family: Theme.fam(text, c.fams)
                font.pixelSize: Math.round(16 * c.s)
            }
            TextInput {
                id: input
                anchors { fill: parent; leftMargin: Math.round(24 * c.s); rightMargin: Math.round(trail.visible ? 52 * c.s : 24 * c.s) }
                verticalAlignment: TextInput.AlignVCenter
                echoMode: c.echo ? TextInput.Normal : TextInput.Password
                passwordCharacter: "•"
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                readOnly: c.busy || c.waiting
                color: c.ink
                selectionColor: Qt.alpha(Theme.accent, 0.4)
                selectedTextColor: c.ink
                font.family: Theme.fam(text, c.fams)
                font.pixelSize: Math.round(16 * c.s)
                font.letterSpacing: c.echo ? 0 : 3
                clip: true
                focus: true
                activeFocusOnTab: true
                cursorVisible: activeFocus && !readOnly
                Accessible.name: c.cue
                onAccepted: c.submit()
                Keys.onEscapePressed: c.cancel()
                Keys.onPressed: event => { if (event.key === Qt.Key_CapsLock) c.capsKey() }
            }
            // The trailing end: Caps Lock's icon, or the circular indicator while PAM checks.
            Item {
                id: trail
                visible: c.capsLock || c.busy
                width: Math.round(24 * c.s)
                height: width
                anchors { right: parent.right; rightMargin: Math.round(18 * c.s); verticalCenter: parent.verticalCenter }
                Icon {
                    anchors.centerIn: parent
                    visible: c.capsLock && !c.busy
                    name: "shift"
                    glyph: "⇪"
                    size: Math.round(22 * c.s)
                    color: c.variant
                    Accessible.name: I18n.tr("lockui.caps_lock")
                }
                Shape {
                    id: spinner
                    visible: c.busy
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Theme.accent
                        strokeWidth: Math.max(2, Math.round(3 * c.s))
                        capStyle: ShapePath.RoundCap
                        fillColor: "transparent"
                        PathAngleArc {
                            centerX: spinner.width / 2; centerY: spinner.height / 2
                            radiusX: spinner.width / 2 - 2; radiusY: radiusX
                            startAngle: -90; sweepAngle: 270
                        }
                    }
                    RotationAnimation on rotation {
                        running: spinner.visible && c.visible && c.moves
                        from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                    }
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: text !== ""
            width: field.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: c.hasError ? c.errorText : c.statusText
            color: c.hasError ? Theme.error : c.variant
            font.family: Theme.fam(text, c.fams)
            font.pixelSize: Math.round(13 * c.s)
        }
    }

    // ---- the fingerprint mark at the foot, above the greeter's strip (only with an enrolled reader) ------------------
    Icon {
        visible: c.primary && c.fingerprint.available === true
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - Math.max(76, 90 * c.s)
        name: "fingerprint"
        glyph: "◎"
        size: Math.round(40 * c.s)
        color: c.fingerprint.state === "scanning" ? Theme.accent : c.variant
    }

    MouseArea { anchors.fill: parent; z: -1; onPressed: c.refocus() }
}
