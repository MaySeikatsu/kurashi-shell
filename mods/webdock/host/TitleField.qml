import QtQuick
import Quickshell
import "core"

// The card's title that is its address field (W76, docs/ux/webdock.md "Round three"; Safari's and Arc's title, Zen's URL
// bar): the page's title as text; a click (or `begin()`) turns it into a field holding the page's address, selected. Enter
// goes there in the same page — the daemon decides whether the text is an address or words for the user's search engine
// (`webdock.go {pin, text}` → `{url}`); a pin stays at its own address (its home), a temporary page's address follows it.
// Esc or a click elsewhere puts the title back; on an empty temporary page ("+") the field is open from the start, and Esc
// drops that page (`webdock.drop`). Nothing runs at rest: the field is an input item, made visible on demand.
Item {
    id: tf

    property var pin: null              // the pin's document entry
    property var page: null             // its WebPage (its engine), when it has one here
    property string title: ""
    property bool bold: false
    property bool centred: false
    property var report: null           // the card's report (logs a refusal)
    readonly property bool debugLog: Quickshell.env("KURASHI_WEBDOCK_DEBUG") === "1"
    // An empty temporary page: the field is open, nothing to show instead.
    readonly property bool blank: !!pin && pin.temporary === true && String(pin.target || "") === ""
    property bool editing: false
    readonly property bool open: editing || blank
    readonly property bool inputFocus: input.activeFocus
    property string error: ""
    // (each edit: the window that holds the keyboard for an empty field keeps holding it while the user types)
    signal typed()

    function begin() {
        if (!pin) return
        editing = true
        error = ""
        input.text = blank ? "" : (page && page.engine ? String(page.engine.url) : String(pin.target || ""))
        input.selectAll()
        input.forceActiveFocus()
        if (debugLog) console.log("webdock-debug field " + pin.id + " edit")
    }
    function end() {
        editing = false
        error = ""
    }
    function submit() {
        var text = input.text.trim()
        if (text === "" || !pin) return
        var p = pin, pg = page
        Store.act("webdock.go", { pin: String(p.id), text: text }, function (m, err) {
            if (err) {
                tf.error = err.msg || "webdock.error.argument"
                if (tf.report) console.warn("webdock: webdock.go refused: " + err.kind + " " + err.msg)
                return
            }
            var url = m && m.data ? String(m.data.url || "") : ""
            if (tf.debugLog) console.log("webdock-debug go " + p.id + " " + url)
            // (a temporary page loads from its target, which the daemon moved; a pin's page goes there itself)
            if (url !== "" && p.temporary !== true && pg && pg.engine) pg.engine.url = url
            tf.end()
            if (pg && pg.engine) pg.engine.forceActiveFocus()
        })
    }
    function cancel() {
        if (blank && pin) Store.act("webdock.drop", { pin: String(pin.id) })
        end()
        if (page && page.engine) page.engine.forceActiveFocus()
    }
    // The empty temporary page takes the keyboard into its field as it appears (the window asks for it: WebCard's pulse).
    function focusField() {
        if (!open || !visible) return
        input.forceActiveFocus()
        if (debugLog) console.log("webdock-debug field " + (pin ? pin.id : "-") + " open")
    }
    onBlankChanged: if (blank) { input.text = ""; error = ""; Qt.callLater(focusField) }
    // (another page: whatever was typed for the last one goes)
    readonly property string pinKey: pin ? String(pin.id) : ""
    onPinKeyChanged: { editing = false; error = ""; input.text = "" }
    onVisibleChanged: if (visible && blank) Qt.callLater(focusField)
    Component.onCompleted: if (blank) Qt.callLater(focusField)

    Text {
        id: label
        anchors.fill: parent
        visible: !tf.open
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: tf.centred ? Text.AlignHCenter : Text.AlignLeft
        elide: Text.ElideRight
        text: tf.title
        color: Theme.fg
        font.pixelSize: Theme.fsLabel
        font.weight: tf.bold ? Theme.wBold : Theme.wRegular
        font.family: Theme.fam(text, Theme.families)
        Accessible.role: Accessible.Button
        Accessible.name: tf.title
        Accessible.description: I18n.tr("webdock.field.edit")
        MouseArea {
            anchors.fill: parent
            enabled: !!tf.pin
            cursorShape: Qt.IBeamCursor
            onClicked: tf.begin()
        }
    }
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: -2
        anchors.bottomMargin: -2
        visible: tf.open
        radius: Theme.rSm
        color: Theme.surface
        border.width: 1
        border.color: input.activeFocus ? Theme.focusRing : Theme.outline
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: Theme.gap
            anchors.rightMargin: Theme.gap
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.fg
            selectByMouse: true
            clip: true
            font.pixelSize: Theme.fsLabel
            font.family: Theme.fam(text, Theme.families)
            Accessible.role: Accessible.EditableText
            Accessible.name: I18n.tr("webdock.field")
            Keys.onReturnPressed: tf.submit()
            Keys.onEnterPressed: tf.submit()
            Keys.onEscapePressed: event => { tf.cancel(); event.accepted = true }
            onTextEdited: { tf.error = ""; tf.typed() }
            // A click elsewhere puts the title back (an empty temporary page keeps its field).
            onActiveFocusChanged: if (!activeFocus && tf.editing && !tf.blank) tf.end()
        }
        Text {
            anchors.fill: input
            visible: input.text === "" && !input.preeditText
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: I18n.tr(tf.error !== "" ? tf.error : "webdock.browse.hint")
            color: tf.error !== "" ? Theme.error : Theme.dim
            font.pixelSize: Theme.fsLabel
            font.family: Theme.fam(text, Theme.families)
        }
    }
}
