import QtQuick

// Test widget (bar, right row, K26): a word in the accent colour. The loader hands over the shell's singletons.
// On a side bar the bar hands `vertical` over, and the word is in two lines, so it keeps to the bar's 36 px.
Text {
    required property var store
    required property var theme
    required property var i18n
    property bool vertical: false
    text: vertical ? "HEL\nLO" : "HELLO"
    horizontalAlignment: Text.AlignHCenter
    color: theme.accent
    font.pixelSize: theme.fs
    Component.onCompleted: console.log("MODQML widget created")
    Component.onDestruction: console.log("MODQML widget destroyed")
}
