import QtQuick
import "../core"

// Caret (W53.8, `[decor] field.caret` / `field.blink`): a text field's cursor as the look draws it — a bar (today's), a
// block one character cell wide (a terminal's, the character under it shows through in the ground's colour) or an
// underscore — and a blink that stops (Ma): it blinks for `field.blink` seconds after the last key, the last move or the
// focus, then rests lit; 0 = steady. Shown only while the field has the keyboard and may be typed in. Used as a
// TextInput's `cursorDelegate` (its parent is the input); `Caret.wanted` says whether a look asks for one at all — while
// it does not, callers keep the toolkit's own caret (today's, pixel-identical).
Item {
    id: c
    readonly property TextInput input: parent instanceof TextInput ? parent : null
    readonly property string form: Theme.decor("field.caret", "bar")
    readonly property int blinkS: Theme.decor("field.blink", -1)
    readonly property real cell: input ? Math.max(4, fm.averageCharacterWidth) : 8
    readonly property real lineH: input ? Math.round(fm.height) : 16
    readonly property bool live: !!input && input.activeFocus && !input.readOnly && input.visible
    property bool lit: true
    // The character the block covers, drawn again in the ground's colour so it stays readable (a terminal's inverse).
    readonly property string under: {
        if (!input || form !== "block" || input.echoMode !== TextInput.Normal) return ""
        var t = input.text
        return input.cursorPosition < t.length ? t.charAt(input.cursorPosition) : ""
    }
    property color ground: Theme.surface

    width: form === "block" ? cell : (form === "underscore" ? cell : Math.max(1, Theme.crisp(Theme.focusW, Screen.devicePixelRatio)))
    height: lineH
    visible: live && lit

    FontMetrics { id: fm; font: c.input ? c.input.font : Qt.font({}) }

    // Restart the blink on every key, move and focus; then let it run out.
    function wake() {
        lit = true
        if (blinkS > 0 && live) { blink.restart(); stopAfter.restart() }
        else { blink.stop(); stopAfter.stop() }
    }
    onLiveChanged: wake()
    Connections {
        target: c.input
        function onTextChanged() { c.wake() }
        function onCursorPositionChanged() { c.wake() }
    }
    Component.onCompleted: wake()
    Timer { id: blink; interval: 530; repeat: true; onTriggered: c.lit = !c.lit }
    Timer { id: stopAfter; interval: Math.max(1, c.blinkS) * 1000; onTriggered: { blink.stop(); c.lit = true } }

    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: parent.width
        height: c.form === "underscore" ? Math.max(2, Math.round(c.lineH / 8)) : parent.height
        antialiasing: false
        color: c.input ? c.input.color : Theme.fg
    }
    Text {
        visible: c.under !== ""
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: c.under
        color: c.ground
        font: c.input ? c.input.font : Qt.font({})
    }
}
