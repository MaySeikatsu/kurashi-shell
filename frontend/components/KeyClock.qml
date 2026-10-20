import QtQuick
import "../core"

// The time as four keys (K42/K43; SekaiPop's lock and desk clock): hour keys on the container, minute keys tonal, the
// colon in the accent. Flat chrome draws the same keys as plain tiles. `hh`/`mm` come from svc.clock; a changed digit
// drops in with a spring, so the clock moves once a minute, on the patch, and never on its own.
Row {
    id: kc
    property string hh: "--"
    property string mm: "--"
    property int keyW: 54
    property int keyH: 72
    property int digitSize: 48
    property bool animate: visible
    spacing: Math.round(keyW / 9)
    Repeater {
        model: [0, 1, -1, 2, 3]
        delegate: Item {
            id: keyItem
            required property int modelData
            readonly property string digits: (kc.hh + kc.mm)
            width: modelData < 0 ? Math.round(kc.keyW / 4) : kc.keyW
            height: kc.keyH + Theme.shadowDy
            Text {
                visible: keyItem.modelData < 0
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -Theme.shadowDy / 2
                color: Theme.accent
                font.pixelSize: Math.round(kc.digitSize * 0.83)
                font.weight: Font.Black
                font.family: Theme.fam(text, Theme.families)
                text: ":"
            }
            Block {
                visible: keyItem.modelData >= 0
                anchors.fill: parent
                radius: Theme.rLg
                ringScale: 0.67
                fill: keyItem.modelData < 2 ? Theme.container : Theme.selected
                flatBorder: Theme.outline
                Text {
                    anchors.centerIn: parent
                    color: keyItem.modelData < 2 ? Theme.fg : Theme.fgOnSelected
                    font.pixelSize: kc.digitSize
                    font.weight: Font.Black
                    font.family: Theme.fam(text, Theme.families)
                    text: keyItem.digits.charAt(Math.max(0, keyItem.modelData))
                    onTextChanged: if (kc.animate && Theme.springOn) drop.restart()
                    NumberAnimation on anchors.verticalCenterOffset {
                        id: drop
                        running: false
                        from: -Math.round(kc.digitSize * 0.3); to: 0
                        duration: Theme.stdMs + 120
                        easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot
                    }
                }
            }
        }
    }
}
