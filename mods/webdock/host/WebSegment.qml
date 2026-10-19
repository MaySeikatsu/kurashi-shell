import QtQuick
import "core"

// A two-option segmented control for the card header (docs/ux/webdock.md "Card": mobile/desktop, phone/large).
// `current` is the key of the chosen option; a press emits `picked` with the other key. Keyboard: Tab, then Return
// or Space picks the option that is not current, like a press.
Rectangle {
    id: seg

    property string keyA: ""
    property string labelA: ""
    property string keyB: ""
    property string labelB: ""
    property string current: ""
    property int fontSize: Theme.fsCaption
    signal picked(string key)

    readonly property int optionW: Math.max(a.implicitWidth, b.implicitWidth) + 2 * Theme.gap

    height: 24
    width: 2 * optionW + 4
    radius: Theme.rFull
    color: Theme.containerHigh
    border.width: 1
    border.color: Theme.outline
    activeFocusOnTab: true
    Keys.onReturnPressed: seg.pick(current === keyA ? keyB : keyA)
    Keys.onSpacePressed: seg.pick(current === keyA ? keyB : keyA)
    Accessible.role: Accessible.ButtonMenu
    Accessible.name: (current === keyA ? labelA : labelB)

    function pick(key) {
        if (key !== current) seg.picked(key)
    }

    Row {
        anchors.centerIn: parent
        spacing: 0

        Rectangle {
            width: seg.optionW
            height: seg.height - 6
            anchors.verticalCenter: parent.verticalCenter
            radius: Theme.rFull
            color: seg.current === seg.keyA ? Theme.accent : "transparent"
            Text {
                id: a
                anchors.centerIn: parent
                text: seg.labelA
                color: seg.current === seg.keyA ? Theme.fgOnAccent : Theme.dim
                font.pixelSize: seg.fontSize
                font.family: Theme.fam(text, Theme.families)
            }
            MouseArea {
                anchors.fill: parent
                onClicked: seg.pick(seg.keyA)
            }
        }
        Rectangle {
            width: seg.optionW
            height: seg.height - 6
            anchors.verticalCenter: parent.verticalCenter
            radius: Theme.rFull
            color: seg.current === seg.keyB ? Theme.accent : "transparent"
            Text {
                id: b
                anchors.centerIn: parent
                text: seg.labelB
                color: seg.current === seg.keyB ? Theme.fgOnAccent : Theme.dim
                font.pixelSize: seg.fontSize
                font.family: Theme.fam(text, Theme.families)
            }
            MouseArea {
                anchors.fill: parent
                onClicked: seg.pick(seg.keyB)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: seg.radius
        color: "transparent"
        border.width: 1
        border.color: Theme.focusRing
        visible: seg.activeFocus
    }
}
