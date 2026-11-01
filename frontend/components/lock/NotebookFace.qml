import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../core"
import ".."

// The notebook face (W53.7, docs/ux/styles.md §9 kami, K60): the lock as a page of the notebook. The paper (the look's
// surface and its K59 relief — kami's dotted stock — or, with the texture off, the page ruled in faint blue at a fixed
// pitch; the two writing lines are ruled either way), the red margin rule (two lines, as exercise books print it) and three
// punched holes down the binding edge; the date written at the head of the page; the time written large by hand (the
// look's Kalam / Klee One) in the pen's ink with the colon in the red correction pen; under it the name and the password
// written on the ruled lines — the password line takes the keys (echo off: dots as a pen would make them; on for a PAM
// question with `prompt_echo`). States: a wrong password is marked in the red pen beside the line (✗ and the message,
// wavy-underlined: no shake, a teacher's mark); Caps Lock is a note in the margin, boxed in red; busy, the countdown and
// PAM's information in pencil under the line; what plays on the page's last line; "daemon disconnected" at its foot.
// The other outputs show the page, the date and the time (`primary` false). Colours from roles (rule 4); static: drawn
// once per size and colour, nothing moves.
FaceBase {
    id: c

    readonly property real s: Math.max(0.75, Math.min(width / 1920, height / 1080))
    readonly property real pitch: Math.round(34 * s)
    readonly property real marginX: Math.round(Math.max(96, width * 0.14))
    readonly property real textX: marginX + Math.round(28 * s)
    readonly property bool busy: lock.busy === true
    readonly property bool waiting: remainingMs > 0
    readonly property bool followUp: (lock.prompt || "") !== ""
    readonly property bool echo: lock.prompt_echo === true
    readonly property string cue: lock.prompt_key ? I18n.tr(lock.prompt_key)
                                  : (lock.prompt ? lock.prompt : I18n.tr("lockui.notebook.password"))
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
    readonly property color ink: Theme.fg
    readonly property color pencil: Qt.alpha(Theme.fg, 0.55)
    readonly property color redPen: Theme.accent
    readonly property color rule: Qt.alpha(Theme.secondary, 0.26)
    readonly property bool mediaOn: !!(media.title || media.artist)
    // The line (counted from the top) each part of the page is written on.
    readonly property int dateLine: 3
    readonly property int clockLine: 9
    readonly property int nameLine: 12
    readonly property int passLine: 14
    function lineY(n) { return n * pitch }
    function fam(t) { return Theme.fam(t, Theme.families) }

    color: Theme.surface

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

    // ---- the page: the K59 relief (the look's paper), the rulings, the margin, the holes ------------------------------
    Loader {
        anchors.fill: parent
        active: Theme.texShell
        sourceComponent: Relief { anchors.fill: parent }
    }
    Repeater {
        model: Math.ceil(c.height / c.pitch)
        Rectangle {
            required property int index
            // Ruled throughout only on plain paper: kami's own stock is dotted, the dots are its ruling.
            visible: index >= 2 && (!Theme.texShell || index === c.nameLine || index === c.passLine)
            y: c.lineY(index)
            width: c.width
            height: 1
            color: c.rule
        }
    }
    Rectangle { x: c.marginX; width: 1; height: c.height; color: Qt.alpha(c.redPen, 0.55) }
    Rectangle { x: c.marginX + 3; width: 1; height: c.height; color: Qt.alpha(c.redPen, 0.35) }
    Repeater {
        model: [0.18, 0.5, 0.82]
        Rectangle {
            required property real modelData
            x: Math.round(c.marginX * 0.38) - width / 2
            y: Math.round(c.height * modelData) - height / 2
            width: Math.round(26 * c.s)
            height: width
            radius: width / 2
            // A hole shows what lies under the page: the paper a shade darker, its rim catching the light.
            color: Qt.darker(Theme.surface, 1.22)
            border.width: 1
            border.color: Qt.alpha(Theme.fg, 0.18)
        }
    }

    // ---- the head of the page: the date, written at the right ---------------------------------------------------------
    Text {
        anchors.right: parent.right
        anchors.rightMargin: Math.round(64 * c.s)
        y: c.lineY(c.dateLine) - height + Math.round(6 * c.s)
        text: {
            var d = c.clock.date ? new Date(c.clock.date + "T12:00:00") : null
            return d ? d.toLocaleDateString(Qt.locale((Store.docs["i18n"] || {}).locale || "en"),
                                             I18n.tr("lockui.notebook.date_format"))
                     : (c.clock.weekday ?? "")
        }
        color: c.ink
        font.family: c.fam(text)
        font.pixelSize: Math.round(26 * c.s)
    }

    // ---- the time, written large --------------------------------------------------------------------------------------
    Row {
        x: c.textX
        y: c.lineY(c.clockLine) - height + Math.round(28 * c.s)
        spacing: Math.round(4 * c.s)
        Text {
            text: c.clock.hh ?? "--"
            color: c.ink
            font.family: Theme.families[0]
            font.pixelSize: Math.round(196 * c.s)
            font.weight: Font.Bold
        }
        Text {
            text: ":"
            color: c.redPen
            font.family: Theme.families[0]
            font.pixelSize: Math.round(196 * c.s)
            font.weight: Font.Bold
        }
        Text {
            text: c.clock.mm ?? "--"
            color: c.ink
            font.family: Theme.families[0]
            font.pixelSize: Math.round(196 * c.s)
            font.weight: Font.Bold
        }
    }

    // ---- the name and the password, on the lines (the focused output) -------------------------------------------------
    Item {
        id: form
        visible: c.primary
        anchors.fill: parent

        Row {
            x: c.textX
            y: c.lineY(c.nameLine) - height + Math.round(7 * c.s)
            spacing: Math.round(14 * c.s)
            Text {
                text: I18n.tr("lockui.notebook.name")
                color: c.pencil
                font.family: c.fam(text)
                font.pixelSize: Math.round(24 * c.s)
                anchors.baseline: who.baseline
            }
            Text {
                id: who
                text: c.userName
                color: c.ink
                font.family: c.fam(text)
                font.pixelSize: Math.round(32 * c.s)
            }
        }

        Text {
            id: label
            x: c.textX
            y: c.lineY(c.passLine) - height + Math.round(7 * c.s)
            text: c.cue
            color: c.pencil
            font.family: c.fam(text)
            font.pixelSize: Math.round(24 * c.s)
        }
        TextInput {
            id: input
            x: label.x + label.width + Math.round(14 * c.s)
            width: Math.round(380 * c.s)
            height: Math.round(c.pitch * 1.2)
            y: c.lineY(c.passLine) - height + Math.round(6 * c.s)
            verticalAlignment: TextInput.AlignBottom
            echoMode: c.echo ? TextInput.Normal : TextInput.Password
            passwordCharacter: "•"
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
            readOnly: c.busy || c.waiting
            color: c.ink
            selectionColor: Qt.alpha(c.redPen, 0.35)
            font.family: Theme.families[0]
            font.pixelSize: Math.round(30 * c.s)
            font.letterSpacing: c.echo ? 0 : 3 * c.s
            clip: true
            focus: true
            activeFocusOnTab: true
            cursorVisible: activeFocus && !readOnly
            opacity: c.busy ? 0.55 : 1
            Accessible.name: c.cue
            onAccepted: c.submit()
            Keys.onEscapePressed: { input.text = ""; c.cancelled() }
            Keys.onPressed: event => { if (event.key === Qt.Key_CapsLock) c.capsKey() }
        }
        // The line under the password, gone over in pencil while it has the keys.
        Rectangle {
            x: input.x - 4
            y: c.lineY(c.passLine)
            width: input.width + 8
            height: Math.max(1, Math.round(2 * c.s))
            color: input.activeFocus ? c.pencil : "transparent"
        }

        // The red pen's mark beside the line: ✗ and the message, a wavy line under it.
        Item {
            id: mark
            visible: c.errorText !== ""
            x: input.x + input.width + Math.round(18 * c.s)
            y: c.lineY(c.passLine) - height + Math.round(6 * c.s)
            width: markText.width
            height: markText.height + Math.round(8 * c.s)
            Text {
                id: markText
                text: "✗ " + c.errorText
                color: c.redPen
                font.family: c.fam(text)
                font.pixelSize: Math.round(26 * c.s)
                width: Math.min(implicitWidth, c.width - mark.x - 40)
                wrapMode: Text.Wrap
            }
            Shape {
                id: wave
                anchors.top: markText.bottom
                width: markText.width
                height: Math.round(6 * c.s)
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: c.redPen
                    strokeWidth: Math.max(1.2, 1.6 * c.s)
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: 0; startY: wave.height / 2
                    PathPolyline {
                        path: {
                            var p = [], n = Math.max(2, Math.floor(wave.width / (10 * c.s)))
                            for (var i = 0; i <= n; i++)
                                p.push(Qt.point(i * wave.width / n, i % 2 ? 0 : wave.height))
                            return p
                        }
                    }
                }
            }
        }

        // Pencil under the line: busy, the countdown, PAM's information, the fingerprint.
        Text {
            visible: text !== ""
            x: c.textX
            y: c.lineY(c.passLine + 2) - height + Math.round(6 * c.s)
            text: c.statusText
            color: c.pencil
            font.family: c.fam(text)
            font.pixelSize: Math.round(24 * c.s)
        }

        // Caps Lock: a note in the margin, boxed in red and turned a little, as one scribbles beside a line.
        Rectangle {
            visible: c.capsLock
            rotation: -7
            x: Math.round(c.marginX * 0.62) - width / 2 + Math.round(c.marginX * 0.18)
            y: c.lineY(c.passLine) - height
            width: capsText.implicitWidth + Math.round(14 * c.s)
            height: capsText.implicitHeight + Math.round(6 * c.s)
            color: "transparent"
            border.width: Math.max(1, Math.round(1.6 * c.s))
            border.color: c.redPen
            radius: 3
            Text {
                id: capsText
                anchors.centerIn: parent
                text: "⇪ " + I18n.tr("lockui.notebook.caps")
                color: c.redPen
                font.family: c.fam(text)
                font.pixelSize: Math.round(20 * c.s)
                font.weight: Font.Bold
            }
            Accessible.role: Accessible.StaticText
            Accessible.name: I18n.tr("lockui.caps_lock")
        }
    }

    // What plays, on the page's last free line (clear of the greeter's strip).
    Text {
        visible: c.mediaOn
        x: c.textX
        y: c.lineY(Math.floor((c.height - 80) / c.pitch)) - height + Math.round(6 * c.s)
        width: c.width - x - 64
        elide: Text.ElideRight
        text: "♪ " + (c.media.title ?? "") + (c.media.artist ? " — " + c.media.artist : "")
        color: c.pencil
        font.family: c.fam(text)
        font.pixelSize: Math.round(22 * c.s)
    }
    Text {
        visible: !Store.live
        anchors.horizontalCenter: parent.horizontalCenter
        y: c.lineY(c.passLine + 4) - height + Math.round(6 * c.s)
        text: I18n.tr("lockui.disconnected")
        color: c.redPen
        font.family: c.fam(text)
        font.pixelSize: Math.round(22 * c.s)
    }

    MouseArea { anchors.fill: parent; z: -1; onPressed: c.refocus() }
}
