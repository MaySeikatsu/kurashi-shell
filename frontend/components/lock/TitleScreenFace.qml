import QtQuick
import Quickshell
import "../../core"

// The title-screen face (W53.5, docs/ux/styles.md §7 "Lock face title-screen"): a 16-bit RPG's lock in two stages, every
// size and place on the output's integer pixel grid (`g = Theme.grid(height)`: 2 logical px on 1080 lines), bitmap type
// (8 × 8 at 8·g·k px), Rectangles without smoothing.
// - The title: a black ground, an original blocky wordmark of the host name (white face, a hard extrusion one grid pixel
//   per step in the X blue), the pad's four face colours as a diamond of dots (X top, A right, B bottom, Y left — roles),
//   and "PUSH ANY KEY", which blinks three times when it appears and then stays lit. The clock and date small at the top
//   right. Never a console maker's logo, "Licensed by" or a "© year" line.
// - The file select: an RPG window (a dark outline 1 g, a white border 2 g, corners stepped one grid pixel, the fill in
//   hard bands `bandTop` → `bandBottom`; one solid fill under high contrast) with "FILE 1  <user>  <hh:mm>" and the
//   password as a name-entry line — a grid-pixel dash under each slot, a drawn gem for each typed character (the typed
//   text itself for a PAM question with echo), a steady block cursor after them — and a CAPS lamp while the keyboard
//   reports Caps Lock. The window grows in the look's held steps (`openCurve` over `openMs`); reduced motion: at once.
// Messages stand in a second window at the bottom (above the greeter's 72 px): it types its line out once (40 chars/s) —
// the error ("That's not it."), PAM's information and questions, the fingerprint — with the retry countdown under it
// (its digits change in place, never retyped), "NOW LOADING" with three stepping dots while busy, and "daemon
// disconnected" (the window greys to two bands). Reduced motion: the whole line at once, no blink, no growth, still dots.
// The field has the keyboard from the first frame, so the key that leaves the title is the password's first character.
// Esc clears the field, then returns to the title; back to the title after 60 s on the file select with nothing typed.
// Other outputs (`primary` false): the title without its prompt. Colours from roles (rule 4). Ma: painted once per size and
// colour; the blink (3 s), the growth (one shot), the type-out (to the line's end) and the dots (while busy) all stop; the
// field's caret is a steady block, never blinking.
FaceBase {
    id: c

    // ---- the grid ------------------------------------------------------------------------------------------------------
    // One grid pixel in logical px (a look without a grid still gets one, from the 224-line screen at ×2).
    readonly property int g: Theme.grid(height) > 0 ? Theme.grid(height) : Math.max(1, Math.round(height / 448))
    function snap(v) { return Math.round(v / g) * g }
    // A length rounded to whole multiples of 4 g, so the four growth steps land on the grid.
    function snap4(v) { return Math.max(4 * g, Math.floor(v / (4 * g)) * 4 * g) }
    function up4(v) { return Math.ceil(v / (4 * g)) * 4 * g }
    // One 8 × 8 character cell at scale k.
    function cell(k) { return 8 * g * k }

    // ---- state ---------------------------------------------------------------------------------------------------------
    readonly property bool busy: lock.busy === true
    readonly property bool waiting: remainingMs > 0
    readonly property bool followUp: (lock.prompt || "") !== ""
    readonly property bool echo: lock.prompt_echo === true
    readonly property bool reduce: !Theme.springOn || !Theme.timed
    readonly property string promptText: lock.prompt_key ? I18n.tr(lock.prompt_key)
                                         : (lock.prompt ? lock.prompt : I18n.tr("lockui.title.password"))
    readonly property string errorText: {
        if (lock.message_key === "lock.error.wrong_password") return I18n.tr("lockui.title.wrong")
        if (lock.message_key) return I18n.tr(lock.message_key)
        if (lock.pam_message && lock.pam_message.kind === "error") return lock.pam_message.text || ""
        return ""
    }
    readonly property string infoText: (lock.pam_message && lock.pam_message.kind !== "error" && lock.pam_message.text)
                                       ? lock.pam_message.text : ""
    readonly property string userName: (user && user.name) ? user.name : String(Quickshell.env("USER") || "")
    readonly property string host: String(Quickshell.env("HOSTNAME") || "") || "暮らし"
    // The error's text box stays until the next key.
    property bool errorSeen: false
    onErrorTextChanged: { errorSeen = errorText === ""; if (errorText !== "") enter() }
    onFollowUpChanged: { field.text = ""; if (followUp) enter(); refocus() }
    onBusyChanged: { if (busy) enter(); else refocus() }
    onWaitingChanged: if (waiting) enter()

    // The file select is up (only the focused output leaves the title).
    property bool fileSelect: false
    readonly property bool onFile: fileSelect && primary
    onOnFileChanged: {
        if (onFile) {
            if (Theme.timed && Theme.springOn) { win.open = 0; grow.restart() } else win.open = 1
        } else {
            grow.stop(); win.open = 0; blinks = 0; field.text = ""
        }
    }

    // ---- inks (roles) --------------------------------------------------------------------------------------------------
    readonly property color ground: Theme.color("color.scrim", "#000000")
    // The title's ink and the window's border: the RPG white (the look's ring), light on the black in either scheme.
    readonly property color white: Theme.color("color.ring", "#f8f8f8")
    readonly property color lineInk: Theme.color("color.line", "#000000")
    readonly property bool banded: Theme.fillBands > 0
    // Text inside a window: on the bands the title's ink; on the solid high-contrast fill the surface's.
    readonly property color winInk: banded ? Theme.color("color.on_title", "#ffffff") : Theme.fg
    readonly property color winDim: banded ? Qt.alpha(winInk, 0.78) : Theme.dim

    color: ground

    function refocus() { field.forceActiveFocus() }
    function enter() { if (primary) fileSelect = true; refocus() }
    function submit() {
        if (field.text === "" || busy || waiting) return
        var s = field.text
        field.text = ""
        c.submitted(s)
        s = ""
    }

    // ---- bitmap type ---------------------------------------------------------------------------------------------------
    component PixText: Text {
        property int k: 1
        color: c.white
        font.pixelSize: c.cell(k)
        font.family: Theme.fam(text, Theme.families)
        font.hintingPreference: Font.PreferFullHinting
        renderType: Text.NativeRendering
        antialiasing: false
    }
    // A block with its four corner pixels cut (`cut` px): a dot, a lamp, a gem.
    component Notched: Item {
        property color fill: c.white
        property int cut: c.g
        Rectangle { x: parent.cut; width: parent.width - 2 * parent.cut; height: parent.height; color: parent.fill; antialiasing: false }
        Rectangle { y: parent.cut; width: parent.width; height: parent.height - 2 * parent.cut; color: parent.fill; antialiasing: false }
    }
    // The RPG window: the snes frame's rings (frames/Snes.qml: a dark outline, then white, light grey and dark grey — Final
    // Fantasy VI's dialogue frame — one grid pixel each), every corner stepped by one grid pixel, the fill in hard bands
    // (`fill.band_h` grid pixels each), black in high contrast (no bands); `grey`: offline, two grey bands. Its size grows with `open` (0..1) about its centre.
    component RpgWindow: Item {
        id: w
        property real open: 1
        property int fullW: 0
        property int fullH: 0
        property bool grey: false
        readonly property int n: grey ? 2 : (c.banded ? Theme.bandCount(fillArea.height, c.g) : 1)
        function greyed(col) { return Qt.hsla(col.hslHue, 0, col.hslLightness, 1) }
        function band(i) {
            if (!c.banded && !grey) return Theme.surface
            var a = c.banded ? Theme.bandTop : Theme.container
            var b = c.banded ? Theme.bandBottom : Qt.darker(Theme.container, 1.5)
            var t = n <= 1 ? 0 : i / (n - 1)
            var col = Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
            return grey ? greyed(col) : col
        }
        width: Math.max(8 * c.g, c.snap(fullW * open))
        height: Math.max(8 * c.g, c.snap(fullH * open))
        visible: open > 0
        Notched { anchors.fill: parent; fill: c.lineInk }
        Notched { anchors.fill: parent; anchors.margins: c.g; fill: c.white }
        Notched { anchors.fill: parent; anchors.margins: 2 * c.g; fill: Theme.color("color.outline", "#b8b8b8") }
        Notched { anchors.fill: parent; anchors.margins: 3 * c.g; fill: Theme.color("color.outline_variant", "#606868") }
        Item {
            id: fillArea
            anchors.fill: parent
            anchors.margins: 4 * c.g
            clip: true
            Repeater {
                model: w.n
                Rectangle {
                    required property int index
                    y: c.snap(index * fillArea.height / w.n)
                    width: fillArea.width
                    height: c.snap((index + 1) * fillArea.height / w.n) - y
                    color: w.band(index)
                    antialiasing: false
                }
            }
            // The fill's own corners stepped too (the frame's inner ring shows through).
            Repeater {
                model: 4
                Rectangle {
                    required property int index
                    x: index % 2 === 0 ? 0 : fillArea.width - c.g
                    y: index < 2 ? 0 : fillArea.height - c.g
                    width: c.g; height: c.g
                    color: Theme.color("color.outline_variant", "#606868")
                    antialiasing: false
                }
            }
        }
    }

    // ---- the clock (every output, every stage) ---------------------------------------------------------------------------
    readonly property var dateObj: {
        if (clock.date) return new Date(clock.date + "T12:00:00")
        if (clock.year && clock.month && clock.day) return new Date(clock.year, clock.month - 1, clock.day, 12)
        return null
    }
    Column {
        x: c.width - width - 8 * c.g
        y: 8 * c.g
        spacing: 4 * c.g
        PixText {
            anchors.right: parent.right
            k: 2
            text: (c.clock.hh ?? "--") + ":" + (c.clock.mm ?? "--")
        }
        PixText {
            anchors.right: parent.right
            k: 1
            color: Qt.alpha(c.white, 0.8)
            text: {
                var d = c.dateObj
                if (!d) return String(c.clock.weekday ?? "").toUpperCase()
                var loc = Qt.locale((Store.docs["i18n"] || {}).locale || "en")
                return d.toLocaleDateString(loc, I18n.tr("lockui.title.date_format")).toUpperCase()
            }
        }
    }

    // ---- the title -----------------------------------------------------------------------------------------------------
    Item {
        id: title
        anchors.fill: parent
        visible: !c.onFile
        readonly property string word: c.host.toUpperCase()
        // The wordmark's scale: as large as fits 84 % of the width, 2..8.
        readonly property int k: Math.max(2, Math.min(8, Math.floor(c.width * 0.84 / Math.max(1, word.length * c.cell(1)))))
        readonly property int depth: k

        Item {
            id: mark
            width: face.implicitWidth + title.depth * c.g
            height: face.implicitHeight + title.depth * c.g
            x: c.snap((c.width - width) / 2)
            y: c.snap(c.height * 0.26)
            // The extrusion: one copy per grid pixel down and right, deepest first, in the X blue.
            Repeater {
                model: title.depth
                PixText {
                    required property int index
                    k: title.k
                    x: (title.depth - index) * c.g
                    y: (title.depth - index) * c.g
                    color: index === 0 ? Qt.darker(Theme.tertiary, 1.8) : Theme.tertiary
                    text: title.word
                }
            }
            PixText { id: face; k: title.k; text: title.word }
        }

        // The pad's four face colours as a diamond: X top (blue), A right (red), B bottom (yellow), Y left (green).
        Item {
            id: pad
            readonly property int d: 10 * c.g
            readonly property int s: 12 * c.g
            width: 2 * s + d
            height: 2 * s + d
            x: c.snap((c.width - width) / 2)
            y: mark.y + mark.height + 16 * c.g
            Repeater {
                model: [
                    [1, 0, Theme.tertiary],
                    [2, 1, Theme.secondary],
                    [1, 2, Theme.warning],
                    [0, 1, Theme.color("color.success", "#40b058")]
                ]
                Notched {
                    required property var modelData
                    x: modelData[0] * pad.s
                    y: modelData[1] * pad.s
                    width: pad.d; height: pad.d
                    cut: 2 * c.g
                    fill: modelData[2]
                }
            }
        }

        // PUSH ANY KEY: blinks three times when the title appears (hard on/off, 0.5 s each), then stays lit.
        PixText {
            id: push
            visible: c.primary && (c.reduce || c.blinks >= 6 || c.blinks % 2 === 0)
            k: 2
            x: c.snap((c.width - width) / 2)
            y: pad.y + pad.height + 24 * c.g
            text: I18n.tr("lockui.title.push")
            Accessible.role: Accessible.Button
            Accessible.name: I18n.tr("lockui.title.start")
            Accessible.onPressAction: c.enter()
        }
        MouseArea {
            anchors.fill: parent
            enabled: c.primary && !c.onFile
            onClicked: c.enter()
        }
    }
    property int blinks: 0
    Timer {
        interval: 500
        repeat: true
        running: c.primary && !c.onFile && !c.reduce && c.blinks < 6 && c.visible
        onTriggered: c.blinks++
    }

    // ---- the file select -----------------------------------------------------------------------------------------------
    readonly property int winW: snap4(Math.min(436 * g, width - 32 * g))
    readonly property int inset: 12 * g          // border 3 g + padding 9 g
    readonly property int innerW: winW - 2 * inset
    readonly property int slotW: cell(2)
    // Slots on the name-entry line: what fits beside the hand and the CAPS lamp.
    readonly property int slots: Math.max(4, Math.floor((innerW - 12 * g - 48 * g) / slotW))

    RpgWindow {
        id: win
        visible: c.onFile && open > 0
        open: 0
        fullW: c.winW
        fullH: c.up4(c.inset * 2 + 76 * c.g)
        grey: !Store.live
        x: c.snap((c.width - width) / 2)
        y: c.snap(c.height * 0.36 + (fullH - height) / 2)

        Item {
            id: fileBody
            visible: win.open >= 1
            x: c.inset; y: c.inset
            width: c.innerW
            height: win.height - 2 * c.inset

            // FILE 1   <user>   <hh:mm>
            PixText {
                k: 2
                color: c.winInk
                text: I18n.tr("lockui.title.file")
            }
            PixText {
                k: 2
                x: c.snap((fileBody.width - width) / 2)
                width: Math.min(implicitWidth, fileBody.width - 2 * c.cell(2) * 7)
                elide: Text.ElideRight
                color: c.winInk
                text: c.userName
            }
            PixText {
                k: 2
                x: fileBody.width - width
                color: c.winInk
                text: (c.clock.hh ?? "--") + ":" + (c.clock.mm ?? "--")
            }

            // The name-entry line's label: PASSWORD, or PAM's question (the text box repeats a question too long for it).
            PixText {
                id: label
                k: 2
                y: 32 * c.g
                width: fileBody.width
                elide: Text.ElideRight
                color: c.winDim
                text: c.promptText
            }

            // The hand, the slots (a dash under each, a gem per typed character, the block cursor), the CAPS lamp.
            Item {
                id: entry
                y: 56 * c.g
                width: fileBody.width
                height: 20 * c.g
                // The cursor hand: a stepped ▶ (four columns of grid pixels).
                Repeater {
                    model: 4
                    Rectangle {
                        required property int index
                        x: index * 2 * c.g
                        y: (1 + 2 * index) * c.g
                        width: 2 * c.g
                        height: (14 - 4 * index) * c.g
                        color: c.winInk
                        antialiasing: false
                    }
                }
                Item {
                    id: slotRow
                    x: 12 * c.g
                    width: c.slots * c.slotW
                    height: parent.height
                    // The last `slots - 1` characters show; the cursor takes the slot after them.
                    readonly property int len: field.displayText.length
                    readonly property int first: Math.max(0, len - (c.slots - 1))
                    Repeater {
                        model: c.slots
                        Item {
                            required property int index
                            readonly property int at: slotRow.first + index
                            x: index * c.slotW
                            width: c.slotW
                            height: slotRow.height
                            // The dash: 6 font pixels of the 8, a grid pixel under the cell.
                            Rectangle {
                                x: 2 * c.g; y: 18 * c.g
                                width: 12 * c.g; height: c.g
                                color: c.winInk
                                antialiasing: false
                            }
                            // A typed character (echo off): a gem, 8 × 8 grid pixels with its corners stepped twice.
                            Notched {
                                visible: !c.echo && parent.at < slotRow.len
                                x: 4 * c.g; y: 4 * c.g
                                width: 8 * c.g; height: 8 * c.g
                                cut: 2 * c.g
                                fill: c.winInk
                            }
                            PixText {
                                visible: c.echo && parent.at < slotRow.len
                                k: 2
                                color: c.winInk
                                text: visible ? field.displayText.charAt(parent.at) : ""
                            }
                            // The block cursor ▮: steady.
                            Rectangle {
                                visible: parent.at === slotRow.len && field.activeFocus && !field.readOnly
                                x: 3 * c.g; y: 0
                                width: 10 * c.g; height: 16 * c.g
                                color: Theme.accent
                                antialiasing: false
                            }
                        }
                    }
                }
                // CAPS: a lamp lit in the warning role while the keyboard reports Caps Lock, dark when it reports it off;
                // absent while unknown (Shōjiki).
                Row {
                    visible: c.lock.caps_lock !== undefined && c.lock.caps_lock !== null
                    anchors.right: parent.right
                    y: 4 * c.g
                    spacing: 2 * c.g
                    Notched {
                        width: 8 * c.g; height: 8 * c.g
                        cut: c.g
                        fill: c.capsLock ? Theme.warning : Qt.darker(c.winDim, 2.2)
                        Accessible.role: Accessible.StaticText
                        Accessible.name: I18n.tr(c.capsLock ? "lockui.title.caps_on" : "lockui.title.caps_off")
                    }
                    PixText {
                        k: 1
                        color: c.capsLock ? c.winInk : c.winDim
                        text: I18n.tr("lockui.title.caps")
                    }
                }
            }
        }
    }
    NumberAnimation {
        id: grow
        target: win
        property: "open"
        from: 0; to: 1
        duration: Theme.openMs
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.openCurve
    }

    // ---- the text box --------------------------------------------------------------------------------------------------
    // Which message stands: its kind keys the type-out, so a countdown ticking or the dots stepping never retypes it.
    readonly property string msgKind: !Store.live ? "offline"
        : busy ? "busy"
        : waiting ? "wait"
        : (errorText !== "" && !errorSeen) ? "error"
        : (followUp && label.truncated) ? "prompt"
        : infoText !== "" ? "info"
        : fingerprint.available === true ? "finger" : ""
    readonly property string msgHead: {
        switch (msgKind) {
        case "offline": return I18n.tr("lockui.disconnected")
        // The dots are part of the line: they step by showing one, two, three of them (the line never changes size).
        case "busy": return I18n.tr("lockui.title.loading") + "..."
        case "wait": return errorText
        case "error": return errorText
        case "prompt": return promptText
        case "info": return infoText
        case "finger": return I18n.tr(fingerprint.state === "scanning" ? "lockui.fingerprint.scanning" : "lockui.fingerprint.idle")
        }
        return ""
    }
    // The line under it that changes in place: the countdown.
    readonly property string msgTail: msgKind === "wait"
        ? I18n.tr("lockui.title.retry_in").replace("{s}", Math.ceil(remainingMs / 1000)) : ""
    property string typedHead: ""
    property int typed: 0
    // How much of the line shows: the type-out, or NOW LOADING with 0..3 of its dots.
    readonly property int shown: msgKind === "busy" ? Math.max(0, typedHead.length - 3 + (reduce ? 3 : dots)) : typed
    onMsgHeadChanged: retype()
    onMsgKindChanged: retype()
    function retype() {
        if (msgHead === typedHead && typed > 0) return
        typedHead = msgHead
        typed = reduce || msgKind === "busy" ? msgHead.length : 0
    }
    readonly property bool boxShown: primary && msgKind !== "" && (onFile || msgKind === "offline")
    Timer {
        // The type-out: one character every 25 ms, stopping at the line's end.
        interval: 25
        repeat: true
        running: c.boxShown && c.typed < c.typedHead.length
        onTriggered: c.typed = Math.min(c.typedHead.length, c.typed + 1)
    }
    property int dots: 0
    Timer {
        // NOW LOADING's dots: only while busy.
        interval: 333
        repeat: true
        running: c.boxShown && c.busy && !c.reduce
        onTriggered: c.dots = (c.dots + 1) % 4
        onRunningChanged: c.dots = 0
    }
    function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }

    RpgWindow {
        id: box
        visible: c.boxShown
        fullW: c.winW
        fullH: c.up4(c.inset * 2 + msgCol.height)
        grey: !Store.live
        x: c.snap((c.width - width) / 2)
        y: c.snap(c.height - 72 - 8 * c.g - height)
        Accessible.role: Accessible.StaticText
        Accessible.name: c.msgHead + (c.msgTail !== "" ? " " + c.msgTail : "")

        Column {
            id: msgCol
            x: c.inset
            y: c.snap((box.height - height) / 2)
            width: c.innerW
            spacing: 8 * c.g
            // The typed part shows; the rest is laid out but clear, so a word never jumps to the next line mid-way.
            // Lines at a pitch of 1.5 cells; the last line's extra space is cut so the box keeps even margins.
            Item {
                visible: c.typedHead !== ""
                width: parent.width
                height: Math.max(1, boxText.lineCount) * c.cell(2) * 1.5 - c.cell(2) * 0.5
                PixText {
                    id: boxText
                    k: 2
                    width: parent.width
                    wrapMode: Text.Wrap
                    lineHeightMode: Text.FixedHeight
                    lineHeight: c.cell(2) * 1.5
                    textFormat: Text.StyledText
                    color: c.winInk
                    font.family: Theme.fam(c.typedHead, Theme.families)
                    text: c.esc(c.typedHead.slice(0, c.shown)) + "<font color=\"transparent\">"
                          + c.esc(c.typedHead.slice(c.shown)) + "</font>"
                }
            }
            PixText {
                visible: c.msgTail !== "" && c.typed >= c.typedHead.length
                k: 2
                color: c.winInk
                text: c.msgTail
            }
        }
    }

    // ---- the field -----------------------------------------------------------------------------------------------------
    // Invisible: the name-entry line draws it. It has the keyboard from the first frame on the focused output.
    TextInput {
        id: field
        x: 0; y: 0
        width: 1; height: 1
        opacity: 0
        enabled: c.primary
        focus: true
        echoMode: c.echo ? TextInput.Normal : TextInput.Password
        passwordCharacter: "*"
        // No caret of its own (it would blink at rest): the name-entry draws a steady block.
        cursorDelegate: Item {}
        readOnly: c.busy || c.waiting
        Accessible.role: Accessible.EditableText
        Accessible.name: c.promptText
        Accessible.passwordEdit: !c.echo
        onTextChanged: if (text !== "") c.errorSeen = true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_CapsLock) c.capsKey()
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) { event.accepted = true; return }
            if (!c.onFile) {
                c.enter()
                // The key that leaves the title is the password's first character, unless it types nothing.
                if (event.text === "" || event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || event.key === Qt.Key_Escape || event.key === Qt.Key_Space)
                    event.accepted = true
            }
        }
        Keys.onReturnPressed: c.submit()
        Keys.onEnterPressed: c.submit()
        Keys.onEscapePressed: {
            if (c.followUp) { text = ""; c.cancelled(); return }
            if (text !== "") text = ""
            else c.fileSelect = false
        }
    }
    MouseArea {
        anchors.fill: parent
        enabled: c.onFile
        z: -1
        onClicked: c.refocus()
    }

    // Back to the title after a minute on the file select with nothing typed.
    Timer {
        interval: 60000
        running: c.onFile && field.text === "" && !c.busy && !c.waiting && !c.followUp
        onTriggered: c.fileSelect = false
    }
}
