import QtQuick
import qs.core
import qs.components

// A quiet choice in the wallpaper picker (docs/ux/wallpaper.md; W19-wallpaper, I83): the target, the sort, the theme
// and the scheme switches. A selected choice is tinted with the accent, not filled, so Apply stays the picker's one
// accent fill. `thumb` (optional) shows a small picture before the label, and only once it is decoded, so a picture
// that is still loading leaves no blank slot. Reached by Tab; Return, Enter and Space choose it; a click chooses it.
Rectangle {
    id: pick
    property string label: ""
    property bool selected: false
    property bool enabled: true
    property string thumb: ""
    signal activated()

    function press() { if (pick.enabled) pick.activated() }

    implicitWidth: content.implicitWidth + 2 * Theme.pad
    implicitHeight: 28
    radius: Theme.rFull
    color: pick.selected ? Qt.alpha(Theme.accent, 0.22) : Theme.containerHigh
    border.width: pick.selected || (hover.hovered && pick.enabled) ? 1 : 0
    border.color: pick.selected ? Theme.accent : Theme.fg
    opacity: pick.enabled ? 1 : 0.5

    activeFocusOnTab: pick.enabled
    Keys.onReturnPressed: pick.press()
    Keys.onEnterPressed: pick.press()
    Keys.onSpacePressed: pick.press()
    Accessible.role: Accessible.Button
    Accessible.name: pick.label
    Accessible.checkable: true
    Accessible.checked: pick.selected

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Theme.xs
        Image {
            id: thumbImg
            Component.onCompleted: Light.addPicture(thumbImg, Window.window)
            Component.onDestruction: Light.removePicture(thumbImg)
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 14
            source: pick.thumb
            sourceSize.width: 48
            sourceSize.height: 28
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fg
            font.pixelSize: Theme.fsLabel
            font.family: Theme.fam(text, Theme.families)
            text: pick.label
        }
    }
    HoverHandler { id: hover }
    MouseArea {
        anchors.fill: parent
        // The hit area grows to the control height (32 px floor); the drawn pill keeps its size.
        anchors.margins: -Math.max(0, (Theme.controlH - pick.height) / 2)
        enabled: pick.enabled
        onClicked: { pick.forceActiveFocus(); pick.press() }
    }
    FocusRing {
        anchors.fill: parent
        corner: pick.radius
        shown: pick.activeFocus
    }
}
