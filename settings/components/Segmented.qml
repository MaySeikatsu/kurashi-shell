import QtQuick
import "../core"

// Choice control: one pill per option; `choices` are schema choices {value, label (i18n key)}.
// Tab enters the group; Left/Up and Right/Down pick the neighbour and move focus with it.
Flow {
    id: s
    property var choices: []
    property var current
    property bool enabled: true
    signal picked(var value)

    spacing: Theme.gap / 2

    function move(from, d) {
        var i = from + d
        if (i < 0 || i >= s.choices.length) return
        var pill = rep.itemAt(i)
        if (!pill || !pill.activeFocusOnTab) return
        pill.forceActiveFocus()
        s.picked(s.choices[i].value)
    }

    Repeater {
        id: rep
        model: s.choices
        delegate: Rectangle {
            id: pill
            required property var modelData
            required property int index
            readonly property bool on: JSON.stringify(modelData.value) === JSON.stringify(s.current)
            implicitWidth: lbl.implicitWidth + 2 * Theme.pad
            implicitHeight: 26
            radius: Theme.rSm
            color: on ? Theme.accent : Theme.containerHigh
            border.width: 1
            border.color: Theme.outline
            opacity: s.enabled ? 1 : 0.5
            activeFocusOnTab: s.enabled
            Keys.onSpacePressed: event => { if (!pill.on) s.picked(modelData.value); event.accepted = true }
            Keys.onReturnPressed: event => { if (!pill.on) s.picked(modelData.value); event.accepted = true }
            Keys.onEnterPressed: event => { if (!pill.on) s.picked(modelData.value); event.accepted = true }
            Keys.onLeftPressed: event => { s.move(pill.index, -1); event.accepted = true }
            Keys.onUpPressed: event => { s.move(pill.index, -1); event.accepted = true }
            Keys.onRightPressed: event => { s.move(pill.index, 1); event.accepted = true }
            Keys.onDownPressed: event => { s.move(pill.index, 1); event.accepted = true }
            Accessible.role: Accessible.RadioButton
            Accessible.name: I18n.tr(modelData.label)
            Accessible.checkable: true
            Accessible.checked: pill.on

            Text {
                id: lbl
                anchors.centerIn: parent
                // Text on the accent fill takes on_accent (4.5:1).
                color: pill.on ? Theme.fgOnAccent : Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr(modelData.label)
            }
            MouseArea {
                anchors.fill: parent
                // The pill keeps its 26 px; the hit area grows to the control height (32 px floor).
                anchors.margins: -Math.max(0, (Theme.controlH - pill.height) / 2)
                enabled: s.enabled
                onClicked: if (!pill.on) s.picked(modelData.value)
            }
            FocusRing {
                anchors.fill: parent
                shown: pill.activeFocus
                corner: pill.radius
            }
        }
    }
}
