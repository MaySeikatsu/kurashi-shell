import QtQuick

// Test slot contribution (K28): a header row in the notification centre.
Text {
    required property var store
    required property var theme
    required property var i18n
    text: "HELLO DND SCHEDULE"
    color: theme.dim
    font.pixelSize: theme.fsCaption
    Component.onCompleted: console.log("MODQML slot notifications.expanded.header created")
    Component.onDestruction: console.log("MODQML slot notifications.expanded.header destroyed")
}
