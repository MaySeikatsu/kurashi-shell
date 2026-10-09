import QtQuick
import QtQuick.Controls
import "../core"

// Dropdown for a `select` row whose offers come from the daemon (I9). The list opens over the whole window
// (Overlay), so a scrolled page never clips it. Enter, Space, Up or Down opens it on the chosen offer; Up and
// Down move the highlight over the offers that can be picked; Enter or Space picks, Escape closes. A greyed
// offer stays in the list with its reason under it. The control keeps the 32 px hit floor (Theme.controlH).
Item {
    id: s
    // Offers {value, label (i18n key), enabled?, reason? (i18n key)}, in the order the daemon gives.
    property var choices: []
    property var current
    property bool enabled: true
    // Accessible name (the row's label); the placeholder shows while nothing is chosen (a pick list's add).
    property string label: ""
    property string placeholder: ""
    signal picked(var value)

    readonly property int chosenIndex: indexOfValue(current)
    readonly property var chosen: chosenIndex >= 0 ? choices[chosenIndex] : null
    // A value no offer names keeps its text here; the row says why it is not in effect (I9, K21).
    readonly property string shown: chosen ? I18n.tr(chosen.label)
        : (current === undefined || current === null ? placeholder : String(current))

    function indexOfValue(v) {
        if (v === undefined || v === null) return -1
        for (var i = 0; i < choices.length; i++)
            if (JSON.stringify(choices[i].value) === JSON.stringify(v)) return i
        return -1
    }
    function firstPickable() {
        for (var i = 0; i < choices.length; i++) if (choices[i].enabled !== false) return i
        return -1
    }
    function open() {
        if (!s.enabled || s.choices.length === 0) return
        var on = s.chosenIndex
        list.currentIndex = on >= 0 && s.choices[on].enabled !== false ? on : s.firstPickable()
        pop.y = s.popupY()
        pop.open()
    }
    function pick(i) {
        if (i < 0 || i >= s.choices.length || s.choices[i].enabled === false) return
        pop.close()
        if (i !== s.chosenIndex) s.picked(s.choices[i].value)
    }
    function step(d) {
        var i = list.currentIndex + d
        while (i >= 0 && i < s.choices.length && s.choices[i].enabled === false) i += d
        if (i >= 0 && i < s.choices.length) list.currentIndex = i
    }
    // Above the control when the window has no room below it, else below. Rows are sized by their
    // lines (one, or two with a reason), so the estimate uses one control height per offer.
    function popupY() {
        var gap = 2
        var h = Math.min(s.choices.length * Theme.controlH, 320) + pop.topPadding + pop.bottomPadding
        var win = Overlay.overlay
        if (!win) return s.height + gap
        var top = s.mapToItem(win, 0, 0).y
        return (top + s.height + gap + h > win.height && top - gap - h >= 0) ? -gap - h : s.height + gap
    }

    implicitWidth: 240
    implicitHeight: Theme.controlH
    opacity: s.enabled ? 1 : 0.5
    activeFocusOnTab: s.enabled
    Accessible.role: Accessible.ComboBox
    Accessible.name: s.label
    Accessible.description: s.shown
    Keys.onReturnPressed: event => { s.open(); event.accepted = true }
    Keys.onEnterPressed: event => { s.open(); event.accepted = true }
    Keys.onSpacePressed: event => { s.open(); event.accepted = true }
    Keys.onDownPressed: event => { s.open(); event.accepted = true }
    Keys.onUpPressed: event => { s.open(); event.accepted = true }

    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        color: Theme.containerHigh
        border.width: 1
        border.color: Theme.outline

        Text {
            id: shownText
            anchors.left: parent.left
            anchors.leftMargin: Theme.pad
            anchors.right: caret.left
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            color: s.chosen ? Theme.fg : Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: s.shown
        }
        Text {
            id: caret
            anchors.right: parent.right
            anchors.rightMargin: Theme.pad
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.dim
            font.pixelSize: Theme.fs
            text: pop.visible ? "▴" : "▾"
        }
        MouseArea {
            anchors.fill: parent
            enabled: s.enabled
            onClicked: pop.visible ? pop.close() : s.open()
        }
        FocusRing {
            anchors.fill: parent
            shown: s.activeFocus
            corner: Theme.rSm
        }
    }

    Popup {
        id: pop
        parent: s
        width: s.width
        padding: 4
        modal: false
        dim: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        onOpened: list.forceActiveFocus()
        // Focus goes back to the control, so Tab carries on from the row (keyboard path).
        onClosed: s.forceActiveFocus()

        background: Rectangle {
            color: Theme.containerHigh
            border.width: 1
            border.color: Theme.outline
            radius: Theme.rSm
        }
        contentItem: ListView {
            id: list
            implicitHeight: Math.min(contentHeight, 320)
            clip: true
            model: s.choices
            // The keys below move the highlight over pickable offers only (a plain ListView would stop on greyed ones).
            keyNavigationEnabled: false
            boundsBehavior: Flickable.StopAtBounds
            Keys.onUpPressed: event => { s.step(-1); event.accepted = true }
            Keys.onDownPressed: event => { s.step(1); event.accepted = true }
            Keys.onReturnPressed: event => { s.pick(list.currentIndex); event.accepted = true }
            Keys.onEnterPressed: event => { s.pick(list.currentIndex); event.accepted = true }
            Keys.onSpacePressed: event => { s.pick(list.currentIndex); event.accepted = true }
            Keys.onEscapePressed: event => { pop.close(); event.accepted = true }

            delegate: Rectangle {
                id: opt
                required property var modelData
                required property int index
                readonly property bool pickable: modelData.enabled !== false
                readonly property bool isChosen: index === s.chosenIndex
                readonly property bool isHighlighted: index === list.currentIndex
                readonly property string reasonText: modelData.reason ? I18n.tr(modelData.reason) : ""
                width: list.width
                height: Math.max(Theme.controlH, captions.implicitHeight + Theme.gap)
                radius: Theme.rSm
                color: isHighlighted ? Theme.container : "transparent"

                Column {
                    id: captions
                    anchors.left: parent.left
                    anchors.right: tick.left
                    anchors.leftMargin: Theme.pad
                    anchors.rightMargin: Theme.gap
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        color: opt.pickable ? Theme.fg : Theme.dim
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr(opt.modelData.label)
                    }
                    Text {
                        visible: opt.reasonText !== ""
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.dim
                        font.pixelSize: Theme.fs - 2
                        font.family: Theme.fam(text, Theme.families)
                        text: opt.reasonText
                    }
                }
                // The chosen offer is marked by a tick, not only by its place in the list.
                Text {
                    id: tick
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.pad
                    anchors.verticalCenter: parent.verticalCenter
                    visible: opt.isChosen
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    text: "✓"
                }
                FocusRing {
                    anchors.fill: parent
                    shown: opt.isHighlighted
                    corner: Theme.rSm
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: opt.pickable
                    onEntered: list.currentIndex = opt.index
                    onClicked: s.pick(opt.index)
                }
                Accessible.role: Accessible.ListItem
                Accessible.name: I18n.tr(opt.modelData.label) + (opt.reasonText !== "" ? ", " + opt.reasonText : "")
                Accessible.selected: opt.isChosen
            }
        }
    }
}
