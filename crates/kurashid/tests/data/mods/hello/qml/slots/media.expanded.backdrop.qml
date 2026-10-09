import QtQuick

// Test slot contribution (K28): a translucent wash behind the media card (fills its host).
Rectangle {
    required property var store
    required property var theme
    required property var i18n
    anchors.fill: parent
    color: "#33c9404b"
    Component.onCompleted: console.log("MODQML slot media.expanded.backdrop created")
    Component.onDestruction: console.log("MODQML slot media.expanded.backdrop destroyed")
}
