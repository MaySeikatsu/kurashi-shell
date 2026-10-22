import QtQuick
import "../core"

// Single-line editor. Enter and leaving the field emit `accepted` with the typed text. The typed text stays while the
// daemon refuses it (the row says why, under the control) and follows the daemon's value once that changes, so an
// invalid input is never replaced by the old value (UX brief, settings: invalid input). Escape puts the daemon's
// value back. `typing` follows every edit, for controls that must react while the user types.
Rectangle {
    id: f
    property string value: ""
    property string placeholder: ""
    property string label: ""
    property bool enabled: true
    property bool mono: false
    property color swatch: "transparent"
    property bool showSwatch: false
    // The daemon refused the typed text (the row's refusal line says why): the edge shows it, not colour alone.
    property bool invalid: false
    signal accepted(string text)
    signal typing(string text)
    // Enter in the field (search jumps to the first hit), and Escape (search clears itself, a row restores its value).
    signal submitted(string text)
    signal escaped()
    // Escape is taken while the field has an edit to take back, or when its owner says it has a use for it (the search
    // clears a query, a form closes); otherwise it goes on up, where the sheet closes on it (K63).
    property bool escapeTaken: false

    // Focus from a shortcut or a keystroke on the list; the caret goes to the end.
    function focusInput() {
        input.forceActiveFocus()
        input.cursorPosition = input.text.length
    }
    function clear() { input.text = "" }
    function restore() { input.text = f.value }
    // The typed text goes out as `accepted` when it differs from the daemon's value (a refused one is sent again).
    function commit(t) { if (t !== f.value) f.accepted(t) }

    implicitWidth: 220
    implicitHeight: Theme.controlH
    radius: Theme.rSm
    color: Theme.containerHigh
    opacity: enabled ? 1 : 0.5
    border.width: f.invalid ? 2 : 0
    border.color: Theme.error

    // The daemon's value is shown whenever it changes while the field is not being edited.
    onValueChanged: if (!input.activeFocus) input.text = f.value

    Rectangle {
        visible: f.showSwatch
        width: 14
        height: 14
        radius: 3
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Theme.gap
        color: f.swatch
        border.width: 1
        border.color: Theme.outline
    }
    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: f.showSwatch ? Theme.gap * 2 + 14 : Theme.gap
        anchors.rightMargin: Theme.gap
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        enabled: f.enabled
        activeFocusOnTab: f.enabled
        color: Theme.fg
        selectionColor: Theme.accent
        selectedTextColor: Theme.fgOnAccent
        font.pixelSize: Theme.fs
        font.family: f.mono ? "monospace" : Theme.fam(text, Theme.families)
        text: f.value
        onTextEdited: f.typing(text)
        // Enter submits and commits the typed text; leaving the field commits it too (TextInput.editingFinished is not
        // relied on: it did not follow Enter in the sandbox, so a typed value was never sent).
        onAccepted: { f.submitted(text); f.commit(text) }
        onActiveFocusChanged: if (!activeFocus) f.commit(text)
        Keys.onEscapePressed: event => {
            const edited = input.text !== f.value
            const taken = edited || f.escapeTaken
            f.restore()
            f.escaped()
            event.accepted = taken
        }
        Accessible.role: Accessible.EditableText
        Accessible.name: f.label !== "" ? f.label : f.placeholder
        Text {
            visible: input.text === "" && !input.activeFocus
            color: Theme.dim
            font: input.font
            anchors.verticalCenter: parent.verticalCenter
            text: f.placeholder
        }
    }
    FocusRing {
        anchors.fill: parent
        shown: input.activeFocus
        corner: f.radius
    }
}
