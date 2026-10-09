import QtQuick

// A small text button for this mod's views, self-contained (mod components cannot import the shell's
// components). Keyboard: Tab reaches it, Return or Space presses it; the focus ring is drawn outside the
// control so it is visible on every surface. An unavailable button says why in its accessible name.
Rectangle {
    id: btn
    required property var theme
    property string label: ""
    property bool active: false
    property bool available: true
    property string reason: ""
    signal activated()

    implicitWidth: caption.implicitWidth + btn.theme.gap * 2
    implicitHeight: Math.max(btn.theme.controlH * 0.75, caption.implicitHeight + btn.theme.xs * 2)
    radius: btn.theme.rFull
    color: active ? btn.theme.containerHigh : btn.theme.container
    border.width: 1
    border.color: btn.activeFocus ? btn.theme.focusRing : btn.theme.outline
    opacity: available ? 1 : 0.45
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: available || reason === "" ? label : label + ", " + reason

    Text {
        id: caption
        anchors.centerIn: parent
        text: btn.label
        color: btn.active ? btn.theme.fg : btn.theme.dim
        font.pixelSize: btn.theme.fsLabel
        font.family: btn.theme.fam(text, btn.theme.families)
    }
    MouseArea {
        anchors.fill: parent
        enabled: btn.available
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.activated()
    }
    Keys.onReturnPressed: if (available) activated()
    Keys.onSpacePressed: if (available) activated()
}
