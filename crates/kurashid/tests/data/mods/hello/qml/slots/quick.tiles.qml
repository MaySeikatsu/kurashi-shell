import QtQuick

// Test slot contribution (K28): a tile at the top of the quick settings card.
Rectangle {
    required property var store
    required property var theme
    required property var i18n
    implicitWidth: 96
    implicitHeight: 40
    radius: 8
    color: theme.containerHigh
    Text { anchors.centerIn: parent; text: "HELLO TILE"; color: theme.fg; font.pixelSize: theme.fsCaption }
    Component.onCompleted: console.log("MODQML slot quick.tiles created")
    Component.onDestruction: console.log("MODQML slot quick.tiles destroyed")
}
