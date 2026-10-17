import QtQuick

// One line of the panel's action menu (the bar's right click): full width, keyboard reachable (Tab, then Return or
// Space), with the reason shown under it when it is unavailable (Shōjiki: an inert control says why).
Rectangle {
    id: row
    required property var theme
    property string label: ""
    property bool available: true
    property string reason: ""
    signal activated()

    width: parent ? parent.width : 0
    implicitHeight: caption.implicitHeight + row.theme.xs * 2 + (reasonText.visible ? reasonText.implicitHeight + row.theme.xs : 0)
    radius: row.theme.rSm
    color: hover.hovered && row.available ? row.theme.containerHigh : "transparent"
    border.width: row.activeFocus ? 1 : 0
    border.color: row.theme.focusRing
    opacity: row.available ? 1 : 0.45
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: row.available || row.reason === "" ? row.label : row.label + ", " + row.reason

    HoverHandler { id: hover }
    Column {
        x: row.theme.gap
        y: row.theme.xs
        width: row.width - row.theme.gap * 2
        spacing: row.theme.xs
        Text {
            id: caption
            width: parent.width
            text: row.label
            color: row.theme.fg
            elide: Text.ElideRight
            font.pixelSize: row.theme.fsLabel
            font.family: row.theme.fam(text, row.theme.families)
        }
        Text {
            id: reasonText
            width: parent.width
            visible: !row.available && row.reason !== ""
            text: row.reason
            color: row.theme.dim
            wrapMode: Text.WordWrap
            font.pixelSize: row.theme.fsCaption
            font.family: row.theme.fam(text, row.theme.families)
        }
    }
    MouseArea {
        anchors.fill: parent
        enabled: row.available
        cursorShape: Qt.PointingHandCursor
        onClicked: row.activated()
    }
    Keys.onReturnPressed: if (row.available) row.activated()
    Keys.onSpacePressed: if (row.available) row.activated()
}
