import QtQuick
import "../../core"
import ".."

// The plain lock face (W53.0b: was LockContent.qml, unchanged at rest, so every look keeps today's lock): one lock
// surface's content (presentational: state in, signals out; the contract is FaceBase's). The password is held only in
// the TextInput, sent through `submitted` and cleared in the same call stack (K2).
// Styling: tokens only. The shake and the countdown run only while the surface exists (= locked).
FaceBase {
    id: c

    readonly property bool busy: lock.busy === true
    readonly property bool waiting: remainingMs > 0
    readonly property bool followUp: (lock.prompt || "") !== ""
    readonly property bool echo: lock.prompt_echo === true
    readonly property string promptText: lock.prompt_key ? I18n.tr(lock.prompt_key)
                                         : (lock.prompt ? lock.prompt : I18n.tr("lockui.prompt.password"))
    readonly property string messageText: {
        if (waiting) return I18n.tr("lockui.retry_in").replace("{s}", Math.ceil(remainingMs / 1000))
        if (lock.message_key) return I18n.tr(lock.message_key)
        if (lock.pam_message && lock.pam_message.text) return lock.pam_message.text
        return ""
    }
    readonly property bool isError: waiting || !!lock.message_key
                                    || !!(lock.pam_message && lock.pam_message.kind === "error")
    readonly property bool mediaOn: !!(media.title || media.artist)

    color: Theme.surface

    // With `texture.text` the relief lies over the lock's text as well.
    Loader {
        z: 1
        anchors.fill: parent
        active: Theme.texShell && Theme.texText
        sourceComponent: Relief { anchors.fill: parent }
    }

    // Keycap chrome (K42; the ring is keycap-only): SekaiPop's dot field — dots that grow toward the top-right and
    // bottom-left corners, drawn once per size (the lock surface exists only while locked).
    Canvas {
        anchors.fill: parent
        visible: Theme.ringW > 0 && !groundFrame.grounds
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        // I124: the colours it paints with; a theme change while locked repaints it.
        readonly property string paintKey: [Theme.line, Theme.outlineColor, Theme.accent, Theme.secondary, Theme.ringW,
            Theme.softR, Theme.outlineW, Theme.shadowDy].join("|")
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

    // The other chromes' grounds (K45), drawn once per size like the dot field, from tokens only (rule 4):
    // an outline with no shadow (line chrome) rules the ground like graph paper in the outline colour; a soft shadow (soft
    // chrome) lays two wide glows of the accent and the secondary under the glass.
    readonly property bool ruled: Theme.outlineW > 0 && Theme.shadowDy <= 0 && Theme.softR <= 0
    Canvas {
        anchors.fill: parent
        // Under a shell texture the material is the ground: no graph paper over it (the glows stay, under the relief).
        visible: ((c.ruled && !Theme.texShell) || Theme.softR > 0) && !groundFrame.grounds
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        // I124: the colours it paints with; a theme change while locked repaints it.
        readonly property string paintKey: [Theme.line, Theme.outlineColor, Theme.accent, Theme.secondary, Theme.ringW,
            Theme.softR, Theme.outlineW, Theme.shadowDy].join("|")
        onPaintKeyChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        onPaint: {
            var g = getContext("2d")
            g.reset()
            if (c.ruled) {
                var step = 28
                g.strokeStyle = Qt.alpha(Theme.outlineColor, 0.16)
                g.lineWidth = 1
                g.beginPath()
                for (var x = 0.5; x < width; x += step) { g.moveTo(x, 0); g.lineTo(x, height) }
                for (var y = 0.5; y < height; y += step) { g.moveTo(0, y); g.lineTo(width, y) }
                g.stroke()
                return
            }
            var spots = [[0.2, 0.25, Theme.accent], [0.8, 0.8, Theme.secondary]]
            for (var i = 0; i < spots.length; i++) {
                var cx = width * spots[i][0], cy = height * spots[i][1], r = Math.max(width, height) * 0.45
                var gr = g.createRadialGradient(cx, cy, 0, cx, cy, r)
                gr.addColorStop(0, Qt.alpha(spots[i][2], 0.22))
                gr.addColorStop(1, Qt.alpha(spots[i][2], 0))
                g.fillStyle = gr
                g.fillRect(0, 0, width, height)
            }
        }
    }

    // The decor pack's ground (W25, K50): the frame's backdrop for the whole surface (shellseikatsu's lockscreen
    // styles, looks only: the column stays where it is). It replaces the chrome-derived grounds above while it draws.
    FrameHost {
        id: groundFrame
        anchors.fill: parent
        kind: "ground"
        animate: c.visible
    }
    // K59: the lock's ground is a material area; the relief lies over the ground's decoration (the dot field, the glows, a
    // decor pack's backdrop) and under the content. The surface is a whole output, so its sheet origin is the output's own.
    Loader {
        anchors.fill: parent
        active: Theme.texShell && !Theme.texText
        sourceComponent: Relief { anchors.fill: parent }
    }

    function refocus() { field.forceActiveFocus() }
    // The hints under the message: Caps Lock (the daemon reads the LED, absent = unknown) and the fingerprint reader
    // (only where PAM asks it and a finger is enrolled).
    readonly property string hintText: {
        var h = []
        if (c.capsLock) h.push(I18n.tr("lockui.caps_lock"))
        if (c.fingerprint.available === true)
            h.push(I18n.tr(c.fingerprint.state === "scanning" ? "lockui.fingerprint.scanning" : "lockui.fingerprint.idle"))
        return h.join(" · ")
    }
    onFollowUpChanged: { field.text = ""; refocus() }
    onBusyChanged: if (!busy) refocus()

    Column {
        id: col
        anchors.centerIn: parent
        spacing: Theme.pad * 2
        width: 380

        // The time as keys (keycap chrome) or plain tiles (flat), SekaiPop's lock clock.
        KeyClock {
            anchors.horizontalCenter: parent.horizontalCenter
            hh: c.clock.hh ?? "--"
            mm: c.clock.mm ?? "--"
            keyW: 76
            keyH: 104
            digitSize: 72
            animate: c.visible
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                var d = c.clock.date ? new Date(c.clock.date + "T12:00:00") : null
                return d ? d.toLocaleDateString(Qt.locale((Store.docs["i18n"] || {}).locale || "en"), "dddd, d MMMM")
                         : (c.clock.weekday ?? "")
            }
            color: Theme.fg
            font.pixelSize: Theme.fsTitle + 2
            font.weight: Theme.wBold
            font.family: Theme.fam(text, Theme.families)
        }

        // ---- password field -----------------------------------------------------------------
        Rectangle {
            id: box
            width: parent.width
            height: 48
            radius: Theme.groups ? Math.min(height / 2, Theme.rFull) : Theme.rLg
            color: Theme.container
            border.width: Theme.outlineW > 0 ? Theme.outlineW + (Theme.ringW > 0 ? 1 : 0) : 1
            border.color: c.isError ? Theme.error : (Theme.ringW > 0 ? Theme.line
                : (field.activeFocus ? Theme.fg : (Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline)))
            SoftShadow { anchors.fill: parent; radius: box.radius }
            // Keycap chrome: the field's hard shadow along the shadow vector (K67; a child below the field, drawn behind it).
            Rectangle {
                z: -1
                visible: Theme.sinkX !== 0 || Theme.sinkY !== 0
                x: Theme.sinkX
                y: Theme.sinkY
                width: box.width
                height: box.height
                radius: box.radius
                color: c.isError ? Theme.error : Theme.line
            }
            opacity: c.busy ? 0.6 : 1

            // Step lengths are shares of the quick motion token (120 ms calm), so the motion profile
            // and speed apply; under motion none they are 0 and the box does not move.
            SequentialAnimation {
                id: shake
                NumberAnimation { target: box; property: "x"; to: 10; duration: Math.round(Theme.quickMs * 0.42) }
                NumberAnimation { target: box; property: "x"; to: -10; duration: Math.round(Theme.quickMs * 0.67) }
                NumberAnimation { target: box; property: "x"; to: 6; duration: Math.round(Theme.quickMs * 0.58) }
                NumberAnimation { target: box; property: "x"; to: 0; duration: Math.round(Theme.quickMs * 0.42) }
            }
            Connections {
                target: c
                function onIsErrorChanged() { if (c.isError && c.visible) shake.restart() }
            }

            Text {
                anchors { left: parent.left; leftMargin: Theme.pad + 6; verticalCenter: parent.verticalCenter }
                visible: field.text === ""
                text: c.promptText
                color: Theme.dim
                font.pixelSize: Theme.fs
                font.family: Theme.families[0]
            }
            TextInput {
                id: field
                anchors { fill: parent; leftMargin: Theme.pad + 6; rightMargin: Theme.pad + 6 }
                verticalAlignment: TextInput.AlignVCenter
                echoMode: c.echo ? TextInput.Normal : TextInput.Password
                passwordCharacter: "•"
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                readOnly: c.busy || c.waiting
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.families[0]
                selectionColor: Theme.accent
                cursorVisible: activeFocus && !readOnly
                focus: true
                Accessible.name: c.promptText
                onAccepted: {
                    if (text === "") return
                    var s = text
                    text = ""                 // clear before anything else can observe it
                    c.submitted(s)
                    s = ""
                }
                Keys.onEscapePressed: { text = ""; c.cancelled() }
                Keys.onPressed: event => { if (event.key === Qt.Key_CapsLock) c.capsKey() }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: c.busy ? I18n.tr("lockui.checking") : c.messageText
            visible: text !== ""
            color: c.isError && !c.busy ? Theme.error : Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            visible: text !== ""
            text: c.hintText
            color: c.capsLock ? Theme.warning : Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            visible: c.mediaOn
            text: (c.media.title ?? "") + (c.media.artist ? " — " + c.media.artist : "")
            color: Theme.dim
            opacity: 0.8
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
        }
    }

    // Veil: daemon away while locked. The session stays locked (compositor-enforced); input is inert.
    Text {
        visible: !Store.live
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: Theme.pad * 2 }
        text: I18n.tr("lockui.disconnected")
        color: Theme.dim
        font.pixelSize: Theme.fs
        font.family: Theme.families[0]
    }
    MouseArea { anchors.fill: parent; onPressed: c.refocus() }
}
