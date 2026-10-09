import QtQuick

// Test face (K24, K28): the compact pill of the hello island face.
Text {
    required property var store
    required property var theme
    required property var i18n
    text: "HELLO FACE"
    color: theme.fg
    font.pixelSize: theme.fs
    Component.onCompleted: console.log("MODQML face created")
    Component.onDestruction: console.log("MODQML face destroyed")
}
