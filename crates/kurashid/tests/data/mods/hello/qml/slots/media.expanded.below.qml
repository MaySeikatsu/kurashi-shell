import QtQuick

// Test slot contribution (K28): a lyrics-like line under the transport.
Text {
    required property var store
    required property var theme
    required property var i18n
    text: "HELLO LYRICS LINE"
    color: theme.accent
    font.pixelSize: theme.fsLabel
    Component.onCompleted: console.log("MODQML slot media.expanded.below created")
    Component.onDestruction: console.log("MODQML slot media.expanded.below destroyed")
}
