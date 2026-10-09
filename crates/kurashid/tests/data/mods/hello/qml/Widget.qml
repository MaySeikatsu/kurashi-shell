import QtQuick

// Test widget (bar, right row, K26): a word in the accent colour. The loader hands over the shell's singletons.
Text {
    required property var store
    required property var theme
    required property var i18n
    text: "HELLO"
    color: theme.accent
    font.pixelSize: theme.fs
    Component.onCompleted: console.log("MODQML widget created")
    Component.onDestruction: console.log("MODQML widget destroyed")
}
