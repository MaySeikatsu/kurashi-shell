import QtQuick
import Quickshell
import "../../core"
import ".."
import "../decor"

// The pastel-os face (W53.6, docs/ux/styles.md §9.1 "Lock face pastel-os"): a login window on a pastel desktop, after
// Needy Streamer Overload's desk (measured on its Steam screenshots, 2 px per art pixel), never its art or words. The
// orchid desk (`desk`) with light-blue dashes stepping down in runs and a few pixel hearts and sparkles, painted once; a
// centred window in the look's frame — 2 px of `outline`, 4 px of the `ring` role's mint, 2 px of `outline` — under a flat pink
// title band ("Log in to <host>", violet pixel type, no buttons: nothing on a lock may pretend to close); in its body a
// pixel heart, the greeting and the user's name, the password field (white, a 2 px violet outline, hearts for the
// characters) and an OK key that submits. A taskbar strip along the foot holds only the clock (no controls). States: a
// wrong password shakes the window once (none under reduce motion) and a speech bubble under the field says why; Caps
// Lock, busy, the countdown and PAM's information are that bubble too; a PAM question relabels the field (echo when it
// asks); "daemon disconnected" in the taskbar. The other outputs show the desk and the taskbar's clock. Colours from
// roles (rule 4); Ma: painted once, the shake one-shot.
FaceBase {
    id: c

    readonly property real s: Math.max(1, Math.round(Math.min(width / 1440, height / 900)))
    readonly property int p: 2 * s
    readonly property bool busy: lock.busy === true
    readonly property bool waiting: remainingMs > 0
    readonly property bool followUp: (lock.prompt || "") !== ""
    readonly property bool echo: lock.prompt_echo === true
    readonly property string cue: lock.prompt_key ? I18n.tr(lock.prompt_key)
                                  : (lock.prompt ? lock.prompt : I18n.tr("lockui.pastel.prompt"))
    readonly property string errorText: {
        if (lock.message_key) return I18n.tr(lock.message_key)
        if (lock.pam_message && lock.pam_message.kind === "error") return lock.pam_message.text || ""
        return ""
    }
    readonly property string statusText: {
        if (busy) return I18n.tr("lockui.checking")
        if (waiting) return I18n.tr("lockui.retry_in").replace("{s}", Math.ceil(remainingMs / 1000))
        if (capsLock) return I18n.tr("lockui.caps_lock")
        if (lock.pam_message && lock.pam_message.kind !== "error" && lock.pam_message.text) return lock.pam_message.text
        if (fingerprint.available === true)
            return I18n.tr(fingerprint.state === "scanning" ? "lockui.fingerprint.scanning" : "lockui.fingerprint.idle")
        return ""
    }
    readonly property string bubble: errorText !== "" ? I18n.tr("lockui.pastel.oops") + " " + errorText : statusText
    readonly property string userName: (user && user.name) ? user.name : String(Quickshell.env("USER") || "")
    readonly property string host: String(Quickshell.env("HOSTNAME") || "") || "暮らし"
    readonly property string fam: Theme.fam(userName, Theme.families)
    readonly property color desk: Theme.color("color.desk", "#f6e1fc")
    readonly property color violet: Theme.outline
    readonly property color mint: Theme.color("color.ring", "#88f0e7")
    readonly property color paper: Theme.color("color.surface", "#fcf9fd")
    readonly property color white: Theme.color("color.surface_container_lowest", "#ffffff")
    readonly property color ink: Theme.fg
    readonly property color pink: Theme.accent
    readonly property color dash: Qt.tint(desk, Qt.rgba(0.55, 0.85, 1.0, 0.55))
    readonly property bool moves: Theme.motionKind !== "none"
    readonly property int fs: 16 * s

    color: desk

    onFollowUpChanged: { input.text = ""; refocus() }
    onBusyChanged: if (!busy) refocus()
    onErrorTextChanged: if (errorText !== "" && c.visible && c.moves) shake.restart()
    function refocus() { input.forceActiveFocus() }
    function submit() {
        if (input.text === "" || c.busy || c.waiting) return
        var t = input.text
        input.text = ""
        c.submitted(t)
        t = ""
    }
    function cancel() { input.text = ""; c.cancelled(); input.forceActiveFocus() }

    // ---- the desk: light-blue dashes stepping down in runs, painted once per size -------------------------------------
    Canvas {
        anchors.fill: parent
        property color tone: c.dash
        onToneChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var g = getContext("2d")
            g.reset()
            g.fillStyle = String(tone)
            var px = c.p
            for (var y0 = 12 * px; y0 < height; y0 += 36 * px)
                for (var x0 = ((y0 / (36 * px)) % 2) * 24 * px; x0 < width; x0 += 48 * px)
                    for (var i = 0; i < 3; i++)
                        g.fillRect(x0 + i * 8 * px, y0 + i * 4 * px, 7 * px, 4 * px)
        }
    }
    // A few pixel hearts and sparkles (fixed places, as shares of the output).
    Repeater {
        model: [[0.12, 0.2, "heart"], [0.83, 0.16, "heart"], [0.08, 0.66, "sparkle"], [0.9, 0.58, "heart"],
                [0.24, 0.84, "sparkle"], [0.7, 0.86, "sparkle"], [0.62, 0.1, "sparkle"], [0.35, 0.12, "heart"]]
        Item {
            required property var modelData
            x: Math.round(c.width * modelData[0])
            y: Math.round(c.height * modelData[1])
            Bullet { visible: parent.modelData[2] === "heart"; kind: "heart"; size: 6 * c.p * 2; ink: Qt.alpha(c.pink, 0.55) }
            Item {
                visible: parent.modelData[2] === "sparkle"
                Rectangle { x: c.p * 2; width: c.p * 2; height: c.p * 6; color: Qt.alpha(c.mint, 0.9) }
                Rectangle { y: c.p * 2; width: c.p * 6; height: c.p * 2; color: Qt.alpha(c.mint, 0.9) }
            }
        }
    }

    // ---- the login window ---------------------------------------------------------------------------------------------
    Item {
        id: win
        visible: c.primary
        width: 220 * c.p
        height: frameCol.height + 16 * c.p
        x: Math.round((c.width - width) / 2) + shakeX
        y: Math.round((c.height - height) / 2 - 20 * c.p)
        property real shakeX: 0
        SequentialAnimation {
            id: shake
            NumberAnimation { target: win; property: "shakeX"; to: -6 * c.p; duration: 50 }
            NumberAnimation { target: win; property: "shakeX"; to: 6 * c.p; duration: 70 }
            NumberAnimation { target: win; property: "shakeX"; to: -4 * c.p; duration: 60 }
            NumberAnimation { target: win; property: "shakeX"; to: 0; duration: 50 }
        }
        // The frame: violet, mint, violet; the paper inside.
        Rectangle { anchors.fill: parent; color: c.violet; antialiasing: false }
        Rectangle { anchors { fill: parent; margins: c.p } color: c.mint; antialiasing: false }
        Rectangle { anchors { fill: parent; margins: 3 * c.p } color: c.violet; antialiasing: false }
        Rectangle { anchors { fill: parent; margins: 4 * c.p } color: c.paper; antialiasing: false }
        Column {
            id: frameCol
            x: 4 * c.p
            y: 4 * c.p
            width: win.width - 8 * c.p
            // The title band.
            Rectangle {
                width: parent.width
                height: 13 * c.p
                color: Theme.color("color.title", "#edc9ed")
                antialiasing: false
                Row {
                    x: 4 * c.p
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3 * c.p
                    Bullet { anchors.verticalCenter: parent.verticalCenter; kind: "heart"; size: 6 * c.p; ink: c.pink }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("lockui.pastel.title").replace("{host}", c.host)
                        color: Theme.color("color.on_title", "#643fb1")
                        font.family: c.fam
                        font.pixelSize: c.fs
                        renderType: Text.NativeRendering
                    }
                }
            }
            Rectangle { width: parent.width; height: c.p; color: c.violet; antialiasing: false }
            Item { width: 1; height: 10 * c.p }
            // The picture: a big pixel heart in a mint square.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 30 * c.p
                height: width
                color: c.white
                border.width: c.p
                border.color: c.violet
                antialiasing: false
                Bullet { anchors.centerIn: parent; kind: "heart"; size: 18 * c.p; ink: c.pink }
            }
            Item { width: 1; height: 5 * c.p }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("lockui.pastel.hello") + ", " + c.userName
                color: c.ink
                font.family: c.fam
                font.pixelSize: c.fs
                renderType: Text.NativeRendering
            }
            Item { width: 1; height: 7 * c.p }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4 * c.p
                // The field: white, a 2 px violet outline, hearts for what is typed.
                Rectangle {
                    id: field
                    width: 140 * c.p
                    height: 14 * c.p
                    color: c.white
                    border.width: c.p
                    border.color: input.activeFocus ? c.violet : Theme.color("color.outline_variant", "#c8b1f6")
                    antialiasing: false
                    Text {
                        anchors { left: parent.left; leftMargin: 4 * c.p; verticalCenter: parent.verticalCenter }
                        visible: input.text === "" && input.preeditText === ""
                        text: c.cue
                        color: Theme.dim
                        font.family: c.fam
                        font.pixelSize: c.fs
                        renderType: Text.NativeRendering
                    }
                    TextInput {
                        id: input
                        anchors { fill: parent; leftMargin: 4 * c.p; rightMargin: 4 * c.p }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: c.echo ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "♥"
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                        readOnly: c.busy || c.waiting
                        color: c.echo ? c.ink : c.pink
                        selectionColor: Qt.alpha(c.pink, 0.4)
                        selectedTextColor: c.ink
                        font.family: c.fam
                        font.pixelSize: c.fs
                        renderType: Text.NativeRendering
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
                // OK: a square outlined key that submits.
                Rectangle {
                    width: 24 * c.p
                    height: 14 * c.p
                    color: okHit.pressed ? Theme.containerHigh : Theme.color("color.surface_container", "#f4dbf9")
                    border.width: c.p
                    border.color: c.violet
                    antialiasing: false
                    opacity: c.busy || c.waiting ? 0.5 : 1
                    Accessible.role: Accessible.Button
                    Accessible.name: okText.text
                    Text {
                        id: okText
                        anchors.centerIn: parent
                        text: I18n.tr("lockui.pastel.ok")
                        color: c.ink
                        font.family: c.fam
                        font.pixelSize: c.fs
                        renderType: Text.NativeRendering
                    }
                    MouseArea { id: okHit; anchors.fill: parent; onClicked: c.submit() }
                }
            }
        }
    }
    // The speech bubble under the window: why, or what is going on.
    Item {
        visible: c.primary && c.bubble !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        y: win.y + win.height + 6 * c.p
        width: Math.min(c.width - 40, msg.implicitWidth + 12 * c.p)
        height: msg.implicitHeight + 8 * c.p + 5 * c.p
        // The tail: three pixel rows pointing up at the window.
        Rectangle { x: Math.round(parent.width / 2) - c.p; y: 0; width: 2 * c.p; height: c.p; color: c.violet }
        Rectangle { x: Math.round(parent.width / 2) - 2 * c.p; y: c.p; width: 4 * c.p; height: c.p; color: c.violet }
        Rectangle { x: Math.round(parent.width / 2) - 3 * c.p; y: 2 * c.p; width: 6 * c.p; height: 3 * c.p; color: c.violet }
        Rectangle {
            y: 5 * c.p
            width: parent.width
            height: parent.height - 5 * c.p
            color: c.white
            border.width: c.p
            border.color: c.violet
            antialiasing: false
            Text {
                id: msg
                anchors.centerIn: parent
                text: c.bubble
                color: c.errorText !== "" ? Theme.error : c.ink
                font.family: c.fam
                font.pixelSize: c.fs
                renderType: Text.NativeRendering
                Accessible.role: c.errorText !== "" ? Accessible.AlertMessage : Accessible.StaticText
                Accessible.name: text
            }
        }
    }

    // ---- the taskbar along the foot: its white top line and the clock (nothing to press) ------------------------------
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 24 * c.p
        color: Theme.color("color.surface_container", "#f4dbf9")
        antialiasing: false
        Rectangle { width: parent.width; height: c.p; color: c.white }
        Rectangle {
            anchors { right: parent.right; rightMargin: 4 * c.p; verticalCenter: parent.verticalCenter }
            width: clock.implicitWidth + 10 * c.p
            height: 16 * c.p
            color: c.paper
            border.width: c.p
            border.color: c.violet
            antialiasing: false
            Text {
                id: clock
                anchors.centerIn: parent
                text: !Store.live ? I18n.tr("lockui.disconnected") : (c.clock.hh ?? "--") + ":" + (c.clock.mm ?? "--")
                color: c.ink
                font.family: c.fam
                font.pixelSize: c.fs
                renderType: Text.NativeRendering
            }
        }
    }

    MouseArea { anchors.fill: parent; z: -1; onPressed: c.refocus() }
}
