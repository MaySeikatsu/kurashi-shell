import QtQuick
import Quickshell
import "../../core"
import ".."
import "../decor"

// The logon face (W53.1, docs/ux/styles.md §1 "Lock face logon"): the bevel era's "Welcome" dialog on the desk ground —
// measured from Windows 98's logon dialog at 1:1 (guidebookgallery.org, pics/gui/startupshutdown/login/win98.png): a
// 458 px dialog with a 3 px raised frame and an 18 px caption that has no buttons (nothing works on a lock), an original
// key glyph, the instruction, "User name" (the session user, read-only: a sunken field on the face, as 9x drew a disabled
// one) and "Password" (a sunken white field, asterisks), OK (the default button, framed in black) and Cancel (clears
// the field: `cancelled`), a taskbar-like strip with the clock in a status well. Every colour is a palette role and every
// metric the bevel tokens, so any look may name it (rule 4).
// States: an error opens a second modal dialog with an original stop glyph and OK (Enter or Esc dismiss it, focus returns
// to the field; the first dialog's caption greys while it is up); Caps Lock is a tooltip-yellow tip under the field; the
// retry delay disables OK and counts down in the status line; PAM's follow-up prompts relabel the field; the fingerprint
// reader's hint replaces the instruction; "daemon disconnected" stands in the strip. On the other outputs only the ground
// and the clock (`primary` false). Ma: painted once per size and colour; nothing runs but the caret while locked.
FaceBase {
    id: c

    readonly property bool busy: lock.busy === true
    readonly property bool waiting: remainingMs > 0
    readonly property bool followUp: (lock.prompt || "") !== ""
    readonly property bool echo: lock.prompt_echo === true
    readonly property string promptText: lock.prompt_key ? I18n.tr(lock.prompt_key)
                                         : (lock.prompt ? lock.prompt : I18n.tr("lockui.logon.password"))
    // An error the user must acknowledge (the stop dialog): the daemon's message, or PAM's error.
    readonly property string errorText: {
        if (lock.message_key) return I18n.tr(lock.message_key)
        if (lock.pam_message && lock.pam_message.kind === "error") return lock.pam_message.text || ""
        return ""
    }
    // What the status line says: busy, the countdown, PAM's information.
    readonly property string statusText: {
        if (busy) return I18n.tr("lockui.checking")
        if (waiting) return I18n.tr("lockui.retry_in").replace("{s}", Math.ceil(remainingMs / 1000))
        if (lock.pam_message && lock.pam_message.kind !== "error" && lock.pam_message.text) return lock.pam_message.text
        return ""
    }
    readonly property string userName: (user && user.name) ? user.name : String(Quickshell.env("USER") || "")
    readonly property string host: String(Quickshell.env("HOSTNAME") || "") || "暮らし"
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    property bool errorOpen: false

    color: Theme.color("color.desk", "#008080")

    onErrorTextChanged: if (errorText !== "" && c.primary) { errorOpen = true; errBox.forceActiveFocus() }
    onFollowUpChanged: { field.text = ""; refocus() }
    onBusyChanged: if (!busy) refocus()

    function refocus() { if (errorOpen) errBox.forceActiveFocus(); else field.forceActiveFocus() }
    function submit() {
        if (field.text === "" || c.busy || c.waiting) return
        var s = field.text
        field.text = ""              // clear before anything else can observe it
        c.submitted(s)
        s = ""
    }
    function cancel() { field.text = ""; c.cancelled(); field.forceActiveFocus() }
    function dismiss() { errorOpen = false; field.forceActiveFocus() }

    // ---- parts -----------------------------------------------------------------------------------------------------
    // A window's raised frame (EDGE_RAISED: light then highlight outside-in, black then shadow) on the face.
    component Frame: Item {
        Rectangle { anchors.fill: parent; color: Theme.surface }
        BevelEdge {
            anchors.fill: parent
            w: Theme.crisp(1, Screen.devicePixelRatio)
            light: Theme.bevelLight2
            light2: Theme.bevelLight
        }
    }
    // A sunken field (shadow then black at the top left, highlight then light at the bottom right).
    component Well: Item {
        property color fill: Theme.color("color.surface_container_lowest", "#ffffff")
        Rectangle { anchors.fill: parent; color: parent.fill }
        BevelEdge {
            anchors.fill: parent
            w: Theme.crisp(1, Screen.devicePixelRatio)
            sunk: true
            dark: Theme.bevelDark2
            dark2: Theme.bevelDark
        }
    }
    // A push button: 75 × 23, raised, sunk while pressed; the default one framed in black; disabled text embossed.
    component Push: Item {
        id: pb
        property string text: ""
        property bool isDefault: false
        signal activated()
        readonly property bool down: (ma.pressed && ma.containsMouse) || keyDown
        property bool keyDown: false
        width: 75
        height: 23
        activeFocusOnTab: enabled
        Accessible.role: Accessible.Button
        Accessible.name: text
        Accessible.onPressAction: if (enabled) activated()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Space) { keyDown = true; event.accepted = true }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { if (enabled) activated(); event.accepted = true }
        }
        Keys.onReleased: event => {
            if (event.key === Qt.Key_Space && keyDown) { keyDown = false; if (enabled) activated(); event.accepted = true }
        }
        Rectangle { anchors.fill: parent; color: pb.isDefault ? Theme.bevelDark : Theme.surface }
        Item {
            anchors.fill: parent
            anchors.margins: pb.isDefault ? Theme.crisp(1, Screen.devicePixelRatio) : 0
            Rectangle { anchors.fill: parent; color: Theme.surface }
            BevelEdge { anchors.fill: parent; w: Theme.crisp(1, Screen.devicePixelRatio); sunk: pb.down }
        }
        // Disabled: the label in the shadow with a highlight copy 1 px down-right (98's embossed grey text).
        PixelLabel {
            visible: !pb.enabled
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 1
            anchors.verticalCenterOffset: 1
            text: pb.text
            color: Theme.bevelLight
        }
        PixelLabel {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: pb.down ? 1 : 0
            anchors.verticalCenterOffset: pb.down ? 1 : 0
            text: pb.text
            color: pb.enabled ? Theme.fg : Theme.bevelDark2
        }
        FocusRing {
            anchors.fill: parent
            shown: pb.activeFocus
            stroke: Theme.fg
        }
        MouseArea { id: ma; anchors.fill: parent; enabled: pb.enabled; onClicked: pb.activated() }
    }
    // A caption without buttons (a lock has nothing to close): the look's caption part when it is this one, drawn from
    // the `[decor] title.*` metrics.
    component Caption: Loader {
        property string text: ""
        property bool focused: true
        height: Theme.crisp(Theme.decor("title.height", 18), Screen.devicePixelRatio)
        source: Qt.resolvedUrl("../decor/title/Classic.qml")
        onLoaded: {
            item.canClose = false
            item.title = Qt.binding(() => text)
            item.active = Qt.binding(() => focused)
        }
    }
    // 32 × 32 glyphs from character maps, painted once per colour: k = ink, then the map's own roles.
    component Glyph: Canvas {
        property var rows: []
        property var inks: ({})
        width: 32
        height: 32
        renderStrategy: Canvas.Cooperative
        readonly property string paintKey: JSON.stringify(inks)
        onPaintKeyChanged: requestPaint()
        onPaint: {
            var g = getContext("2d")
            g.reset()
            for (var y = 0; y < rows.length; y++)
                for (var x = 0; x < rows[y].length; x++) {
                    var ink = inks[rows[y][x]]
                    if (!ink) continue
                    g.fillStyle = ink
                    g.fillRect(x, y, 1, 1)
                }
        }
    }

    // ---- the strip and its clock well (every output) ---------------------------------------------------------------
    Item {
        id: strip
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 28
        Rectangle { anchors.fill: parent; color: Theme.surface }
        Rectangle { y: 0; width: parent.width; height: c.hair; color: Theme.bevelLight2 }
        Rectangle { y: c.hair; width: parent.width; height: c.hair; color: Theme.bevelLight }
        // The daemon is away: said in a status well at the start (the session stays locked).
        Item {
            visible: !Store.live
            x: 2; y: 4
            width: away.implicitWidth + 12
            height: 22
            Well { anchors.fill: parent; fill: Theme.surface }
            PixelLabel { id: away; x: 6; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("lockui.disconnected") }
        }
        Item {
            anchors { right: parent.right; rightMargin: 2; verticalCenter: parent.verticalCenter; verticalCenterOffset: 1 }
            width: time.implicitWidth + 22
            height: 22
            // The tray's 1 px status well: shadow top-left, highlight bottom-right.
            Rectangle { anchors.fill: parent; color: Theme.surface }
            Rectangle { width: parent.width; height: c.hair; color: Theme.bevelDark2 }
            Rectangle { width: c.hair; height: parent.height; color: Theme.bevelDark2 }
            Rectangle { y: parent.height - c.hair; width: parent.width; height: c.hair; color: Theme.bevelLight }
            Rectangle { x: parent.width - c.hair; width: c.hair; height: parent.height; color: Theme.bevelLight }
            PixelLabel {
                id: time
                anchors.centerIn: parent
                text: (c.clock.hh ?? "--") + ":" + (c.clock.mm ?? "--")
            }
        }
    }

    // ---- the logon dialog (the focused output) ---------------------------------------------------------------------
    Item {
        id: dlg
        visible: c.primary
        width: 458
        // 141 px as 98's, a row more for the status line and for the Caps Lock tip.
        height: 141 + (c.statusText !== "" ? 20 : 0) + (c.capsLock ? 26 : 0)
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - strip.height - 141) / 2 - 40)
        Frame { anchors.fill: parent }
        Caption {
            x: 3; y: 3
            width: parent.width - 6
            text: I18n.tr("lockui.logon.title").replace("{host}", c.host)
            focused: !c.errorOpen
        }
        Glyph {
            x: 20; y: 32
            // An original key: a ring bow, the shaft and two bits, brass with a light edge and a shadow.
            rows: [
                "",
                "",
                "",
                "",
                "      kkkkk",
                "    kkhhhhbkk",
                "   khhbbbbbbbk",
                "  khbbbbbbbbbbk",
                "  khbbbkkkkbbbbk",
                " khbbbk    kbbbk",
                " khbbk      kbbbk",
                " khbbk      kbbbk",
                " khbbk      kbbbk",
                " khbbk      kbbbk",
                " kbbbbk    kbbbbk",
                "  kbbbbkkkkbbbbkk",
                "  kbbbbbbbbbbbbbhk",
                "   kbbbbbbbbbbbbbhk",
                "    kkbbbbbbbkkbbbbhk",
                "      kkkkkkksskbbbbhk",
                "              skbbbbhk",
                "               skbbbbhk",
                "                skbbbbhk",
                "                 skbbbbhkk",
                "                  skbbbbbbhk",
                "                   skbbbbkbbk",
                "                    skbbkkbbk",
                "                     skbbbbk",
                "                      skbbk",
                "                       skk"
            ]
            inks: ({ "k": String(Theme.fg), "b": String(Theme.color("color.tertiary", "#808000")),
                     "h": String(Theme.color("color.info", "#ffffe1")), "s": String(Theme.bevelDark2) })
        }
        PixelLabel {
            x: 94; y: 32
            width: 260
            text: c.fingerprint.available === true
                ? I18n.tr(c.fingerprint.state === "scanning" ? "lockui.fingerprint.scanning" : "lockui.fingerprint.idle")
                : I18n.tr("lockui.logon.instruction")
        }
        PixelLabel { x: 94; y: 72; text: I18n.tr("lockui.logon.user") }
        Well {
            x: 166; y: 68
            width: 133; height: 21
            fill: Theme.surface
            PixelLabel { x: 4; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 8; text: c.userName }
        }
        PixelLabel { x: 94; y: 103; width: 70; text: c.promptText }
        Well {
            id: fieldWell
            x: 166; y: 98
            width: 133; height: 21
            opacity: c.busy ? 0.6 : 1
            TextInput {
                id: field
                anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                verticalAlignment: TextInput.AlignVCenter
                echoMode: c.echo ? TextInput.Normal : TextInput.Password
                // 9x hid a password behind asterisks.
                passwordCharacter: "*"
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                readOnly: c.busy || c.waiting
                color: Theme.fg
                selectionColor: Theme.accent
                selectedTextColor: Theme.fgOnAccent
                font.family: Theme.families[0]
                font.pixelSize: Theme.fs
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                clip: true
                focus: true
                activeFocusOnTab: true
                cursorVisible: activeFocus && !readOnly
                Accessible.name: c.promptText
                onAccepted: c.submit()
                Keys.onEscapePressed: c.cancel()
                Keys.onPressed: event => { if (event.key === Qt.Key_CapsLock) c.capsKey() }
            }
        }
        // The status line: busy, the countdown, PAM's information.
        PixelLabel {
            visible: c.statusText !== ""
            x: 94; y: 128
            width: 260
            text: c.statusText
        }
        // Caps Lock: a tooltip-yellow tip under the field.
        Rectangle {
            visible: c.capsLock
            x: 166; y: 122 + (c.statusText !== "" ? 20 : 0)
            width: capsText.implicitWidth + 8
            height: 19
            color: Theme.color("color.info", "#ffffe1")
            border.width: c.hair
            border.color: Theme.bevelDark
            PixelLabel {
                id: capsText
                anchors.centerIn: parent
                text: I18n.tr("lockui.caps_lock")
                color: Theme.color("color.on_info", "#000000")
            }
        }
        Push {
            id: ok
            x: 371; y: 33
            isDefault: true
            text: I18n.tr("lockui.logon.ok")
            enabled: !c.busy && !c.waiting
            onActivated: c.submit()
        }
        Push {
            x: 371; y: 63
            text: I18n.tr("lockui.logon.cancel")
            onActivated: c.cancel()
        }
    }

    // ---- the stop dialog (an error to acknowledge) -----------------------------------------------------------------
    FocusScope {
        id: errBox
        visible: c.primary && c.errorOpen
        width: Math.max(260, Math.min(420, errText.implicitWidth + 80))
        height: 104
        x: Math.round((parent.width - width) / 2)
        y: dlg.y + 50
        Keys.onPressed: event => {
            if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Escape, Qt.Key_Space].indexOf(event.key) >= 0) {
                c.dismiss(); event.accepted = true
            }
        }
        Frame { anchors.fill: parent }
        Caption {
            x: 3; y: 3
            width: parent.width - 6
            text: I18n.tr("lockui.logon.error_title")
        }
        Glyph {
            x: 12; y: 30
            // An original stop sign: a red disc with a white cross and a shadow.
            rows: [
                "",
                "          rrrrrrrrr",
                "        rrrrrrrrrrrrr",
                "      rrrrrrrrrrrrrrrrr",
                "     rrrrrrrrrrrrrrrrrrr",
                "    rrrrrrrrrrrrrrrrrrrrr",
                "   rrrrrrrrrrrrrrrrrrrrrrrs",
                "   rrrrrwwrrrrrrrrrwwrrrrrs",
                "  rrrrrwwwwrrrrrrrwwwwrrrrrs",
                "  rrrrrrwwwwrrrrrwwwwrrrrrrs",
                "  rrrrrrrwwwwrrrwwwwrrrrrrrs",
                " rrrrrrrrrwwwwrwwwwrrrrrrrrrs",
                " rrrrrrrrrrwwwwwwwrrrrrrrrrrs",
                " rrrrrrrrrrrwwwwwrrrrrrrrrrrs",
                " rrrrrrrrrrwwwwwwwrrrrrrrrrrs",
                " rrrrrrrrrwwwwrwwwwrrrrrrrrrs",
                "  rrrrrrrwwwwrrrwwwwrrrrrrrss",
                "  rrrrrrwwwwrrrrrwwwwrrrrrrs",
                "  rrrrrwwwwrrrrrrrwwwwrrrrrs",
                "   rrrrrwwrrrrrrrrrwwrrrrrss",
                "   rrrrrrrrrrrrrrrrrrrrrrrs",
                "    rrrrrrrrrrrrrrrrrrrrrss",
                "     rrrrrrrrrrrrrrrrrrrss",
                "      rrrrrrrrrrrrrrrrrss",
                "        rrrrrrrrrrrrrss",
                "          rrrrrrrrrsss",
                "            sssssss"
            ]
            inks: ({ "r": String(Theme.error), "w": String(Theme.bevelLight), "s": String(Theme.bevelDark2) })
        }
        PixelLabel {
            id: errText
            x: 56; y: 40
            width: parent.width - 66
            text: c.errorText
        }
        Push {
            x: Math.round((parent.width - width) / 2); y: 70
            isDefault: true
            focus: true
            text: I18n.tr("lockui.logon.ok")
            onActivated: c.dismiss()
        }
    }

    MouseArea { anchors.fill: parent; z: -1; onPressed: c.refocus() }
}
