import QtQuick
import "../core"

// Two options, one switch (UX brief, controls: "2 options → switch"). Both names stay visible and the accent knob sits
// under the chosen one, so it reads as a choice, not as on/off. Left, Up, Right and Down move to the other option
// (`previewed`); Space, Return and a click on a side pick it (`picked`); Escape is `cancelled`.
Item {
    id: s
    property var choices: []        // two {value, label (i18n key)}
    property var current
    property bool enabled: true
    property string label: ""
    signal picked(var value)
    signal previewed(var value)
    signal cancelled()

    readonly property int chosenIndex: {
        for (var i = 0; i < choices.length; i++)
            if (JSON.stringify(choices[i].value) === JSON.stringify(current)) return i
        return 0
    }
    readonly property real cellW: Math.max(first.implicitWidth, second.implicitWidth) + 2 * Theme.pad

    function go(i) {
        if (!s.enabled || i < 0 || i >= s.choices.length || i === s.chosenIndex) return
        s.previewed(s.choices[i].value)
    }

    implicitWidth: 2 * cellW
    implicitHeight: Theme.controlH
    activeFocusOnTab: s.enabled
    Accessible.role: Accessible.RadioButton
    Accessible.name: s.label
    Accessible.description: I18n.tr(s.choices[s.chosenIndex] ? s.choices[s.chosenIndex].label : "")
    Keys.onLeftPressed: event => { s.go(0); event.accepted = true }
    Keys.onUpPressed: event => { s.go(0); event.accepted = true }
    Keys.onRightPressed: event => { s.go(1); event.accepted = true }
    Keys.onDownPressed: event => { s.go(1); event.accepted = true }
    Keys.onSpacePressed: event => { s.picked(s.choices[s.chosenIndex].value); event.accepted = true }
    Keys.onReturnPressed: event => { s.picked(s.choices[s.chosenIndex].value); event.accepted = true }
    Keys.onEnterPressed: event => { s.picked(s.choices[s.chosenIndex].value); event.accepted = true }
    Keys.onEscapePressed: event => { s.cancelled(); event.accepted = true }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: 2 * s.cellW
        height: 26
        radius: Theme.rSm
        color: Theme.containerHigh
        border.width: 1
        border.color: Theme.outline
        opacity: s.enabled ? 1 : 0.5

        Rectangle {
            x: 1 + s.chosenIndex * s.cellW
            y: 1
            width: s.cellW - 2
            height: track.height - 2
            radius: Theme.rSm - 1
            color: Theme.accent
        }
        Row {
            anchors.fill: parent
            Text {
                width: s.cellW
                height: parent.height
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: s.chosenIndex === 0 ? Theme.fgOnAccent : Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: s.choices[0] ? I18n.tr(s.choices[0].label) : ""
                id: first
            }
            Text {
                width: s.cellW
                height: parent.height
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: s.chosenIndex === 1 ? Theme.fgOnAccent : Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: s.choices[1] ? I18n.tr(s.choices[1].label) : ""
                id: second
            }
        }
        MouseArea {
            // The track is 26 px; the hit area is the control's 32 px height.
            anchors.fill: parent
            anchors.margins: -3
            enabled: s.enabled
            onClicked: mouse => s.picked(s.choices[mouse.x < track.width / 2 ? 0 : 1].value)
        }
    }
    FocusRing {
        anchors.fill: track
        anchors.margins: -3
        shown: s.activeFocus
        corner: track.radius + 3
    }
}
