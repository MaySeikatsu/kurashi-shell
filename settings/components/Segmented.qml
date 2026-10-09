import QtQuick
import "../core"

// Choice control: one pill per option; `choices` are schema choices {value, label (i18n key)}.
Flow {
    id: s
    property var choices: []
    property var current
    property bool enabled: true
    signal picked(var value)

    spacing: Theme.gap / 2
    Repeater {
        model: s.choices
        delegate: Rectangle {
            required property var modelData
            readonly property bool on: JSON.stringify(modelData.value) === JSON.stringify(s.current)
            implicitWidth: lbl.implicitWidth + 2 * Theme.pad
            implicitHeight: 26
            radius: Theme.rSm
            color: on ? Theme.accent : Theme.containerHigh
            border.width: 1
            border.color: Theme.outline
            opacity: s.enabled ? 1 : 0.5
            Text {
                id: lbl
                anchors.centerIn: parent
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr(modelData.label)
            }
            MouseArea {
                anchors.fill: parent
                enabled: s.enabled
                onClicked: if (!parent.on) s.picked(modelData.value)
            }
        }
    }
}
