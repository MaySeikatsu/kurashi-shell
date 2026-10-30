import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import "../../core"
import ".."
import "../decor"

// The glass logon face (W53.2, docs/ux/styles.md §3 "Lock face logon-glass"): the glass era's logon screen, after
// Windows 7's (its layout from memory and 7's own UX guide idioms; no 1:1 capture of 7's logon was available, so the
// metrics are estimates the brief marks "to verify"). A deep blue ground (`desk`) with a bloom of light behind the tile and
// an original pattern of soft light bands — static, painted once; never 7's "Harmony" art — the user picture in a glass
// frame, the name in light type with a soft shadow, the password field with its grey cue text and a round glass → button;
// low in the middle the host name as the wordmark (never 7's). Shown at once (a keyboard-first lock). Widgets keep 7's
// 1024 × 768 proportions (`s`).
// States (7's own behaviour): a wrong password replaces the field with the message and an OK button — Enter, Space or Esc
// return to the field; Caps Lock raises a balloon from the field (the look's tooltip part); busy ("Welcome"-style line),
// the countdown, PAM's information and the fingerprint reader a line under the field; a PAM question relabels the cue
// text (echo when it asks); "daemon disconnected" low on the left with the clock and date. The other outputs show the
// ground, the wordmark and the clock (`primary` false). Colours from roles (rule 4); Ma: one paint per size and colour.
FaceBase {
    id: c

    readonly property real s: Math.max(1, Math.min(width / 1024, height / 768))
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
    readonly property string host: String(Quickshell.env("HOSTNAME") || "") || "暮らし"
    readonly property string fam: Theme.fam(userName, Theme.families)
    // 7 swaps the field for the message and an OK button until it is acknowledged.
    property bool errorOpen: false
    onErrorTextChanged: if (errorText !== "") { errorOpen = true; if (c.primary) okButton.forceActiveFocus() }

    readonly property color ground: Theme.color("color.desk", "#1c5a9e")
    readonly property color light: Theme.color("color.title", "#74b8fc")
    readonly property color white: Qt.rgba(1, 1, 1, 1)

    color: ground

    onFollowUpChanged: { input.text = ""; refocus() }
    onBusyChanged: if (!busy) refocus()
    function refocus() { if (errorOpen) okButton.forceActiveFocus(); else input.forceActiveFocus() }
    function submit() {
        if (input.text === "" || c.busy || c.waiting) return
        var t = input.text
        input.text = ""             // clear before anything else can observe it
        c.submitted(t)
        t = ""
    }
    function cancel() { input.text = ""; c.cancelled(); input.forceActiveFocus() }
    function dismiss() { errorOpen = false; input.forceActiveFocus() }

    // ---- the ground: depth, a bloom, soft bands of light ------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.darker(c.ground, 1.35) }
            GradientStop { position: 0.45; color: c.ground }
            GradientStop { position: 1; color: Qt.darker(c.ground, 1.5) }
        }
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // The bloom behind the tile.
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: c.width / 2; centerY: c.height * 0.42
                focalX: centerX; focalY: centerY
                centerRadius: c.height * 0.55
                GradientStop { position: 0; color: Qt.alpha(Qt.lighter(c.light, 1.1), 0.42) }
                GradientStop { position: 1; color: Qt.alpha(c.light, 0) }
            }
            startX: 0; startY: 0
            PathLine { x: c.width; y: 0 }
            PathLine { x: c.width; y: c.height }
            PathLine { x: 0; y: c.height }
            PathLine { x: 0; y: 0 }
        }
        // Three soft bands sweeping across, an original pattern (static).
        ShapePath {
            strokeColor: "transparent"
            fillColor: Qt.alpha(c.white, 0.05)
            startX: -c.width * 0.05; startY: c.height * 0.78
            PathQuad { x: c.width * 1.05; y: c.height * 0.36; controlX: c.width * 0.45; controlY: c.height * 0.38 }
            PathLine { x: c.width * 1.05; y: c.height * 0.46 }
            PathQuad { x: -c.width * 0.05; y: c.height * 0.9; controlX: c.width * 0.5; controlY: c.height * 0.5 }
        }
        ShapePath {
            strokeColor: "transparent"
            fillColor: Qt.alpha(c.light, 0.07)
            startX: -c.width * 0.05; startY: c.height * 0.66
            PathQuad { x: c.width * 1.05; y: c.height * 0.12; controlX: c.width * 0.62; controlY: c.height * 0.3 }
            PathLine { x: c.width * 1.05; y: c.height * 0.18 }
            PathQuad { x: -c.width * 0.05; y: c.height * 0.72; controlX: c.width * 0.6; controlY: c.height * 0.36 }
        }
        ShapePath {
            strokeColor: Qt.alpha(c.white, 0.12)
            strokeWidth: 1.5
            fillColor: "transparent"
            startX: -c.width * 0.05; startY: c.height * 0.84
            PathQuad { x: c.width * 1.05; y: c.height * 0.5; controlX: c.width * 0.4; controlY: c.height * 0.5 }
        }
    }

    // ---- low: the wordmark, the clock, daemon state (every output) --------------------------------------------------
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.82)
        spacing: Math.round(10 * c.s)
        PaneMark { size: Math.round(26 * c.s); lift: 0.15; glow: 0.4; anchors.verticalCenter: parent.verticalCenter }
        Text {
            text: c.host
            color: c.white
            font.family: c.fam
            font.pixelSize: Math.round(24 * c.s)
            font.weight: Font.Light
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    Column {
        x: Math.round(28 * c.s)
        y: Math.round(parent.height * 0.82)
        Text {
            text: (c.clock.hh ?? "--") + ":" + (c.clock.mm ?? "--")
            color: c.white
            font.family: c.fam
            font.pixelSize: Math.round(20 * c.s)
            font.weight: Font.Light
        }
        Text {
            text: {
                var d = c.clock.date ? new Date(c.clock.date + "T12:00:00") : null
                return d ? d.toLocaleDateString(Qt.locale((Store.docs["i18n"] || {}).locale || "en"), "dddd, d MMMM") : (c.clock.weekday ?? "")
            }
            color: Qt.alpha(c.white, 0.85)
            font.family: c.fam
            font.pixelSize: Math.round(11 * c.s)
        }
        Text {
            visible: !Store.live
            text: I18n.tr("lockui.disconnected")
            color: c.white
            font.family: c.fam
            font.pixelSize: Math.round(11 * c.s)
        }
    }

    // ---- the tile, the name, the field (the focused output) ---------------------------------------------------------
    Column {
        id: centre
        visible: c.primary
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.42 - frame.height / 2 - 20 * c.s)
        spacing: Math.round(12 * c.s)
        // The glass frame round the picture.
        Item {
            id: frame
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(154 * c.s)
            height: width
            RectangularShadow {
                anchors.fill: parent
                radius: Math.round(10 * c.s)
                blur: 18 * c.s
                color: Qt.rgba(0, 0, 0, 0.45)
                offset.y: 3 * c.s
            }
            Rectangle {
                anchors.fill: parent
                radius: Math.round(10 * c.s)
                color: Qt.alpha(Qt.lighter(c.light, 1.1), 0.35)
                border.width: 1
                border.color: Qt.alpha(c.white, 0.75)
            }
            Rectangle {
                x: 2; y: 2
                width: parent.width - 4; height: parent.height * 0.48
                radius: Math.round(9 * c.s)
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.alpha(c.white, 0.5) }
                    GradientStop { position: 1; color: Qt.alpha(c.white, 0.08) }
                }
            }
            Rectangle {
                id: pic
                anchors.centerIn: parent
                width: Math.round(126 * c.s)
                height: width
                radius: Math.round(3 * c.s)
                clip: true
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(c.ground, 1.5) }
                    GradientStop { position: 1; color: Qt.darker(c.ground, 1.1) }
                }
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.35)
                Text {
                    anchors.centerIn: parent
                    visible: img.status !== Image.Ready
                    text: c.userName.charAt(0).toUpperCase()
                    color: Qt.alpha(c.white, 0.95)
                    font.family: c.fam
                    font.pixelSize: Math.round(60 * c.s)
                    font.weight: Font.Light
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
                }
            }
        }
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: nameText.implicitWidth
            height: nameText.implicitHeight
            Text { x: 1; y: 1; text: nameText.text; font: nameText.font; color: Qt.rgba(0, 0, 0, 0.5) }
            Text {
                id: nameText
                text: c.userName
                color: c.white
                font.family: c.fam
                font.pixelSize: Math.round(24 * c.s)
                font.weight: Font.Light
            }
        }
        // The field and its → button, or (after a wrong password) the message and OK.
        Item {
            id: row
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(225 * c.s) + Math.round(8 * c.s) + Math.round(28 * c.s)
            height: c.errorOpen ? errCol.height : Math.round(28 * c.s)
            Rectangle {
                id: well
                visible: !c.errorOpen
                width: Math.round(225 * c.s)
                height: Math.round(25 * c.s)
                anchors.verticalCenter: parent.verticalCenter
                radius: Math.round(2 * c.s)
                color: Theme.color("color.surface_container_lowest", "#ffffff")
                border.width: 1
                border.color: input.activeFocus ? Qt.lighter(c.light, 1.1) : Qt.rgba(0, 0, 0, 0.35)
                opacity: c.busy ? 0.7 : 1
                Text {
                    anchors { left: parent.left; leftMargin: Math.round(6 * c.s); verticalCenter: parent.verticalCenter }
                    visible: input.text === ""
                    text: c.cue
                    color: Theme.color("color.on_surface_variant", "#6d6d6d")
                    font.family: c.fam
                    font.pixelSize: Math.round(12 * c.s)
                    font.italic: true
                }
                TextInput {
                    id: input
                    anchors { fill: parent; leftMargin: Math.round(6 * c.s); rightMargin: Math.round(6 * c.s) }
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: c.echo ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "●"
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    readOnly: c.busy || c.waiting
                    color: Theme.color("color.on_surface", "#000000")
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.fgOnAccent
                    font.family: c.fam
                    font.pixelSize: Math.round(12 * c.s)
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
            // The round glass → button.
            Item {
                id: go
                visible: !c.errorOpen
                x: well.width + Math.round(8 * c.s)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(28 * c.s)
                height: width
                opacity: c.busy || c.waiting ? 0.55 : 1
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("lockui.welcome.go")
                Accessible.onPressAction: c.submit()
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.5)
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(Theme.accent, goHit.containsMouse ? 1.9 : 1.6) }
                        GradientStop { position: 0.5; color: Theme.accent }
                        GradientStop { position: 1; color: Qt.lighter(Theme.accent, 1.3) }
                    }
                }
                Rectangle {
                    x: parent.width * 0.15; y: 2
                    width: parent.width * 0.7; height: parent.height * 0.45
                    radius: height / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.alpha(c.white, 0.65) }
                        GradientStop { position: 1; color: Qt.alpha(c.white, 0.05) }
                    }
                }
                Shape {
                    id: arrow
                    anchors.centerIn: parent
                    width: Math.round(12 * c.s); height: Math.round(10 * c.s)
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Qt.rgba(0, 0, 0, 0.35)
                        strokeWidth: 1
                        fillColor: c.white
                        startX: 0; startY: arrow.height * 0.36
                        PathLine { x: arrow.width * 0.5; y: arrow.height * 0.36 }
                        PathLine { x: arrow.width * 0.5; y: 0 }
                        PathLine { x: arrow.width; y: arrow.height * 0.5 }
                        PathLine { x: arrow.width * 0.5; y: arrow.height }
                        PathLine { x: arrow.width * 0.5; y: arrow.height * 0.64 }
                        PathLine { x: 0; y: arrow.height * 0.64 }
                        PathLine { x: 0; y: arrow.height * 0.36 }
                    }
                }
                MouseArea { id: goHit; anchors.fill: parent; hoverEnabled: true; onClicked: c.submit() }
            }
            // 7's error: the message in place of the field, OK under it.
            Column {
                id: errCol
                visible: c.errorOpen
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Math.round(14 * c.s)
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.round(300 * c.s)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: c.errorText
                    color: c.white
                    font.family: c.fam
                    font.pixelSize: Math.round(13 * c.s)
                }
                FocusScope {
                    id: okButton
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.round(75 * c.s)
                    height: Math.round(23 * c.s)
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.tr("lockui.logon.ok")
                    Accessible.onPressAction: c.dismiss()
                    Keys.onPressed: event => {
                        if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Escape, Qt.Key_Space].indexOf(event.key) >= 0) {
                            c.dismiss(); event.accepted = true
                        }
                    }
                    DecorHost {
                        id: okFace
                        slot: "button"
                        anchors.fill: parent
                        onLoaded: {
                            item.primary = true
                            item.hovered = Qt.binding(function () { return okHit.containsMouse })
                            item.pressed = Qt.binding(function () { return okHit.pressed })
                        }
                    }
                    Rectangle {
                        visible: !okFace.has
                        anchors.fill: parent
                        radius: 3
                        color: Theme.color("color.surface_container_low", "#f2f2f2")
                        border.width: 1
                        border.color: Theme.accent
                    }
                    Text {
                        anchors.centerIn: parent
                        text: I18n.tr("lockui.logon.ok")
                        color: Theme.color("color.on_surface", "#000000")
                        font.family: c.fam
                        font.pixelSize: Math.round(12 * c.s)
                    }
                    FocusRing { anchors.fill: parent; shown: okButton.activeFocus }
                    MouseArea { id: okHit; anchors.fill: parent; hoverEnabled: true; onClicked: c.dismiss() }
                }
            }
        }
        Text {
            visible: c.statusText !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: c.statusText
            color: c.white
            font.family: c.fam
            font.pixelSize: Math.round(12 * c.s)
        }
    }

    // ---- Caps Lock: a balloon from the field ------------------------------------------------------------------------
    TooltipStyle { id: ts }
    Item {
        visible: c.primary && c.capsLock && !c.errorOpen
        x: centre.x + row.x + Math.round(10 * c.s)
        y: centre.y + row.y + row.height + Math.round(18 * c.s)
        width: Math.round(250 * c.s)
        height: capsCol.implicitHeight + Math.round(18 * c.s)
        Loader {
            anchors.fill: parent
            active: ts.has
            source: ts.part
            onLoaded: { item.tailSide = "top"; item.tailAt = Math.round(24 * c.s) }
        }
        Rectangle {
            visible: !ts.has
            anchors.fill: parent
            radius: 3
            color: Theme.color("color.info", "#ffffff")
            border.width: 1
            border.color: Theme.color("color.outline", "#767676")
        }
        Column {
            id: capsCol
            x: Math.round(10 * c.s)
            y: Math.round(9 * c.s)
            width: parent.width - 2 * x
            spacing: Math.round(3 * c.s)
            Text {
                text: I18n.tr("lockui.caps_lock")
                color: ts.ink(Theme.color("color.on_info", "#1e1e1e"))
                font.family: c.fam
                font.pixelSize: Math.round(12 * c.s)
                font.weight: Font.DemiBold
            }
            Text {
                width: capsCol.width
                wrapMode: Text.WordWrap
                text: I18n.tr("lockui.welcome.caps_hint")
                color: ts.ink(Theme.color("color.on_info", "#1e1e1e"))
                font.family: c.fam
                font.pixelSize: Math.round(11 * c.s)
            }
        }
    }

    MouseArea { anchors.fill: parent; z: -1; onPressed: c.refocus() }
}
