import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../core"
import ".."
import "../decor"

// The welcome face (W53.2, docs/ux/styles.md §2 "Lock face welcome"): the glossy era's Welcome screen, laid out on
// Windows XP's at 1:1 proportions (measured on guidebookgallery.org's pics/gui/startupshutdown/login/winxppro.png,
// 800 × 600): a deep blue header band (13 %) with a light rule under it, the Luna field (`desk`) lit from its top left, a
// faint vertical divider at the middle, the orange rule (`tertiary`) over a deep footer band (16 %). Left of the divider
// the original mark and the host name in italic, and "To begin, type your password"; right of it the user tile — a band
// fading from deep blue into the field, rounded on its left, a gold frame round the picture (`~/.face`, else the
// initial), the name, the prompt, the white field and the green → button. Shown at once, never behind a click (a
// keyboard-first lock). Widgets keep XP's 1024 × 768 proportions (`s`).
// States: a wrong password raises an XP balloon from the field (the look's tooltip part: `[slots] tooltip`), gone at the
// next key; Caps Lock a balloon of its own while it is on; busy, the retry countdown, PAM's information and the
// fingerprint reader a line under the name; a PAM question relabels the prompt (echo on when it asks); "daemon
// disconnected" in the footer. The clock and date stand in the footer (every output); the other outputs show only the
// ground, the bands and the clock (`primary` false). No "Turn off computer": nothing there would act (Shōjiki), and the
// greeter's strip owns the bottom 72 px. Colours from roles (rule 4). Ma: painted once per size and colour; only the caret
// runs while locked.
FaceBase {
    id: c

    readonly property real s: Math.max(1, Math.min(width / 1024, height / 768))
    readonly property bool busy: lock.busy === true
    readonly property bool waiting: remainingMs > 0
    readonly property bool followUp: (lock.prompt || "") !== ""
    readonly property bool echo: lock.prompt_echo === true
    readonly property string promptText: lock.prompt_key ? I18n.tr(lock.prompt_key)
                                         : (lock.prompt ? lock.prompt : I18n.tr("lockui.welcome.prompt"))
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
    // The error balloon stays until the next key.
    property bool errorSeen: false
    onErrorTextChanged: errorSeen = errorText === ""

    readonly property color field: Theme.color("color.desk", "#5a7edc")
    readonly property color deep: Qt.darker(Theme.color("color.title", "#0055e5"), 1.5)
    readonly property color rule: Theme.tertiary

    color: field

    onFollowUpChanged: { input.text = ""; refocus() }
    onBusyChanged: if (!busy) refocus()
    function refocus() { input.forceActiveFocus() }
    function submit() {
        if (input.text === "" || c.busy || c.waiting) return
        var t = input.text
        input.text = ""             // clear before anything else can observe it
        c.submitted(t)
        t = ""
    }
    function cancel() { input.text = ""; c.cancelled(); input.forceActiveFocus() }

    // ---- the ground -------------------------------------------------------------------------------------------------
    // The light from the top left.
    Shape {
        anchors.fill: parent
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: c.width * 0.08; centerY: c.height * 0.2
                focalX: centerX; focalY: centerY
                centerRadius: c.width * 0.32
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.3) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
            }
            startX: 0; startY: 0
            PathLine { x: c.width; y: 0 }
            PathLine { x: c.width; y: c.height }
            PathLine { x: 0; y: c.height }
            PathLine { x: 0; y: 0 }
        }
    }
    Rectangle {
        id: header
        width: parent.width
        height: Math.round(parent.height * 0.13)
        color: c.deep
    }
    Rectangle {
        y: header.height
        width: parent.width
        height: 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.tint(c.field, Qt.rgba(1, 1, 1, 0.05)) }
            GradientStop { position: 0.5; color: Qt.tint(c.field, Qt.rgba(1, 1, 1, 0.6)) }
            GradientStop { position: 1; color: Qt.tint(c.field, Qt.rgba(1, 1, 1, 0.05)) }
        }
    }
    Rectangle {
        id: footer
        anchors.bottom: parent.bottom
        width: parent.width
        height: Math.round(parent.height * 0.157)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.tint(c.deep, Qt.rgba(0.35, 0.2, 0.6, 0.35)) }
            GradientStop { position: 0.6; color: Qt.darker(c.deep, 1.05) }
            GradientStop { position: 1; color: c.deep }
        }
    }
    Rectangle {
        anchors.bottom: footer.top
        width: parent.width
        height: 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.darker(c.deep, 1.1) }
            GradientStop { position: 0.25; color: Qt.lighter(c.rule, 1.12) }
            GradientStop { position: 0.5; color: Qt.tint(c.rule, Qt.alpha(c.field, 0.35)) }
            GradientStop { position: 1; color: Qt.alpha(c.field, 0) }
        }
    }
    // The divider.
    Rectangle {
        visible: c.primary
        x: Math.round(parent.width / 2)
        y: header.height + parent.height * 0.08
        width: 1
        height: footer.y - y - parent.height * 0.08
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(c.field, 0) }
            GradientStop { position: 0.5; color: Qt.tint(c.field, Qt.rgba(1, 1, 1, 0.45)) }
            GradientStop { position: 1; color: Qt.alpha(c.field, 0) }
        }
    }

    // ---- the footer: daemon state, the clock (every output) ----------------------------------------------------------
    Text {
        visible: !Store.live
        x: Math.round(24 * c.s)
        y: footer.y + Math.round(20 * c.s)
        text: I18n.tr("lockui.disconnected")
        color: Qt.rgba(1, 1, 1, 0.92)
        font.family: c.fam
        font.pixelSize: Math.round(13 * c.s)
    }
    Column {
        anchors { right: parent.right; rightMargin: Math.round(32 * c.s) }
        y: footer.y + Math.round(14 * c.s)
        spacing: 0
        Text {
            anchors.right: parent.right
            text: (c.clock.hh ?? "--") + ":" + (c.clock.mm ?? "--")
            color: Qt.rgba(1, 1, 1, 1)
            font.family: c.fam
            font.pixelSize: Math.round(22 * c.s)
        }
        Text {
            anchors.right: parent.right
            text: {
                var d = c.clock.date ? new Date(c.clock.date + "T12:00:00") : null
                return d ? d.toLocaleDateString(Qt.locale((Store.docs["i18n"] || {}).locale || "en"), "dddd, d MMMM") : (c.clock.weekday ?? "")
            }
            color: Qt.rgba(1, 1, 1, 0.85)
            font.family: c.fam
            font.pixelSize: Math.round(11 * c.s)
        }
    }

    // ---- left: the mark, the host, the instruction -------------------------------------------------------------------
    Item {
        visible: c.primary
        anchors { right: parent.horizontalCenter; rightMargin: Math.round(40 * c.s) }
        y: Math.round(parent.height * 0.4)
        width: Math.max(word.implicitWidth + mark.width, begin.implicitWidth)
        height: Math.round(130 * c.s)
        PaneMark {
            id: mark
            size: Math.round(48 * c.s)
            lift: 0.1
            anchors { right: word.left; rightMargin: Math.round(8 * c.s); bottom: word.verticalCenter }
        }
        Text {
            id: word
            anchors.right: parent.right
            y: Math.round(30 * c.s)
            text: c.host
            color: Qt.rgba(1, 1, 1, 1)
            font.family: Theme.tok("font.start", "") || c.fam
            font.pixelSize: Math.round(34 * c.s)
            font.italic: true
            font.weight: Font.Bold
        }
        Text {
            id: begin
            anchors.right: parent.right
            y: Math.round(98 * c.s)
            text: I18n.tr("lockui.welcome.begin")
            color: Qt.rgba(1, 1, 1, 1)
            font.family: c.fam
            font.pixelSize: Math.round(17 * c.s)
        }
    }

    // ---- right: the user tile ----------------------------------------------------------------------------------------
    Item {
        id: tile
        visible: c.primary
        x: Math.round(parent.width / 2 + 27 * c.s)
        y: Math.round(parent.height * 0.487 - height / 2)
        width: parent.width - x
        height: Math.round((78 + (c.statusText !== "" ? 18 : 0)) * c.s)
        Rectangle {
            anchors.fill: parent
            topLeftRadius: Math.round(8 * c.s)
            bottomLeftRadius: Math.round(8 * c.s)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.darker(c.field, 1.62) }
                GradientStop { position: 0.85; color: c.field }
            }
        }
        Rectangle {
            x: Math.round(8 * c.s); width: parent.width; height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.tint(c.field, Qt.rgba(1, 1, 1, 0.5)) }
                GradientStop { position: 0.85; color: Qt.alpha(c.field, 0) }
            }
        }
        // The picture in its gold frame.
        Rectangle {
            id: frame
            x: Math.round(10 * c.s)
            y: Math.round(9 * c.s)
            width: Math.round(52 * c.s)
            height: width
            radius: Math.round(3 * c.s)
            color: Qt.lighter(c.rule, 1.2)
            Rectangle {
                anchors { fill: parent; margins: Math.max(1, Math.round(1 * c.s)) }
                radius: Math.round(2 * c.s)
                color: Qt.tint(Qt.lighter(c.rule, 1.3), Qt.rgba(1, 0.95, 0.3, 0.6))
            }
            Rectangle {
                id: pic
                anchors { fill: parent; margins: Math.round(2 * c.s) }
                color: Qt.darker(c.field, 1.3)
                clip: true
                Text {
                    anchors.centerIn: parent
                    visible: img.status !== Image.Ready
                    text: c.userName.charAt(0).toUpperCase()
                    color: Qt.rgba(1, 1, 1, 0.95)
                    font.family: c.fam
                    font.pixelSize: Math.round(26 * c.s)
                    font.weight: Font.Bold
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
        Text {
            id: name
            x: frame.x + frame.width + Math.round(13 * c.s)
            y: Math.round(9 * c.s)
            text: c.userName
            color: Qt.rgba(1, 1, 1, 1)
            font.family: c.fam
            font.pixelSize: Math.round(17 * c.s)
        }
        Text {
            id: ask
            x: name.x
            y: name.y + name.height + Math.round(2 * c.s)
            text: c.promptText
            color: Qt.rgba(1, 1, 1, 0.95)
            font.family: c.fam
            font.pixelSize: Math.round(11 * c.s)
        }
        // The field: white, the caret, bullets.
        Rectangle {
            id: well
            x: name.x - Math.round(4 * c.s)
            y: ask.y + ask.height + Math.round(4 * c.s)
            width: Math.round(161 * c.s)
            height: Math.round(25 * c.s)
            radius: Math.round(3 * c.s)
            color: Theme.color("color.surface_container_lowest", "#ffffff")
            opacity: c.busy ? 0.7 : 1
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
                font.pixelSize: Math.round(13 * c.s)
                clip: true
                focus: true
                activeFocusOnTab: true
                cursorVisible: activeFocus && !readOnly
                Accessible.name: c.promptText
                onAccepted: c.submit()
                onTextChanged: if (text !== "") c.errorSeen = true
                Keys.onEscapePressed: c.cancel()
                Keys.onPressed: event => { if (event.key === Qt.Key_CapsLock) c.capsKey() }
            }
        }
        // The green → button.
        Rectangle {
            id: go
            x: well.x + well.width + Math.round(12 * c.s)
            y: well.y
            width: Math.round(23 * c.s)
            height: Math.round(24 * c.s)
            radius: Math.round(3 * c.s)
            color: Qt.rgba(1, 1, 1, 1)
            opacity: c.busy || c.waiting ? 0.55 : 1
            Accessible.role: Accessible.Button
            Accessible.name: I18n.tr("lockui.welcome.go")
            Accessible.onPressAction: c.submit()
            Rectangle {
                anchors { fill: parent; margins: Math.max(1, Math.round(1 * c.s)) }
                radius: Math.round(2 * c.s)
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(Theme.secondary, goHit.containsMouse ? 1.45 : 1.3) }
                    GradientStop { position: 0.5; color: Theme.secondary }
                    GradientStop { position: 1; color: Qt.darker(Theme.secondary, 1.45) }
                }
            }
            // The arrow: a shaft and a head, white.
            Shape {
                id: arrow
                anchors.centerIn: parent
                width: Math.round(13 * c.s); height: Math.round(11 * c.s)
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: Qt.rgba(1, 1, 1, 1)
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
        Text {
            visible: c.statusText !== ""
            x: name.x
            y: well.y + well.height + Math.round(5 * c.s)
            width: tile.width - x - Math.round(20 * c.s)
            elide: Text.ElideRight
            text: c.statusText
            color: Qt.rgba(1, 1, 1, 0.95)
            font.family: c.fam
            font.pixelSize: Math.round(11 * c.s)
        }
    }

    // ---- balloons: a wrong password, Caps Lock ----------------------------------------------------------------------
    TooltipStyle { id: ts }
    Item {
        id: balloon
        readonly property bool err: c.errorText !== "" && !c.errorSeen
        visible: c.primary && (err || c.capsLock)
        x: tile.x + well.x - Math.round(14 * c.s)
        y: tile.y + well.y + well.height + Math.round(20 * c.s)
        width: Math.round(300 * c.s)
        height: body.implicitHeight + Math.round(20 * c.s)
        // The look's balloon (its tail up to the field); a plain info box when the look has none.
        Loader {
            anchors.fill: parent
            active: ts.has
            source: ts.part
            onLoaded: { item.tailSide = "top"; item.tailAt = Math.round(30 * c.s) }
        }
        Rectangle {
            visible: !ts.has
            anchors.fill: parent
            radius: 4
            color: Theme.color("color.info", "#ffffe1")
            border.width: 1
            border.color: Theme.color("color.on_info", "#000000")
        }
        Column {
            id: body
            x: Math.round(10 * c.s)
            y: Math.round(9 * c.s)
            width: parent.width - 2 * x
            spacing: Math.round(4 * c.s)
            Row {
                spacing: Math.round(6 * c.s)
                // An error disc with a white cross, or a warning triangle with "!".
                Item {
                    width: Math.round(16 * c.s); height: width
                    Rectangle {
                        visible: balloon.err
                        anchors.fill: parent
                        radius: width / 2
                        color: Theme.error
                        Text { anchors.centerIn: parent; text: "×"; color: Qt.rgba(1, 1, 1, 1); font.pixelSize: Math.round(14 * c.s); font.weight: Font.Bold }
                    }
                    Shape {
                        visible: !balloon.err
                        anchors.fill: parent
                        ShapePath {
                            strokeColor: Qt.darker(Theme.tertiary, 1.4)
                            fillColor: Qt.lighter(Theme.tertiary, 1.2)
                            startX: 8 * c.s; startY: 1
                            PathLine { x: 15 * c.s; y: 15 * c.s }
                            PathLine { x: 1; y: 15 * c.s }
                            PathLine { x: 8 * c.s; y: 1 }
                        }
                    }
                    Text {
                        visible: !balloon.err
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Math.round(3 * c.s)
                        text: "!"
                        color: Theme.color("color.on_info", "#000000")
                        font.pixelSize: Math.round(11 * c.s)
                        font.weight: Font.Bold
                    }
                }
                Text {
                    text: balloon.err ? c.errorText : I18n.tr("lockui.caps_lock")
                    color: ts.ink(Theme.color("color.on_info", "#000000"))
                    font.family: c.fam
                    font.pixelSize: Math.round(11 * c.s)
                    font.weight: Font.Bold
                }
            }
            Text {
                width: body.width
                wrapMode: Text.WordWrap
                text: I18n.tr(balloon.err ? "lockui.welcome.error_hint" : "lockui.welcome.caps_hint")
                color: ts.ink(Theme.color("color.on_info", "#000000"))
                font.family: c.fam
                font.pixelSize: Math.round(11 * c.s)
            }
        }
    }

    MouseArea { anchors.fill: parent; z: -1; onPressed: c.refocus() }
}
