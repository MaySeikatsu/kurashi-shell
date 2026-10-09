import QtQuick

// Test face, expanded view (K24, K28): the card under the island while the hello face is shown.
Text {
    required property var store
    required property var theme
    required property var i18n
    text: "HELLO FACE, EXPANDED"
    color: theme.fg
    font.pixelSize: theme.fsTitle
    Component.onCompleted: console.log("MODQML face-expanded created")
    Component.onDestruction: console.log("MODQML face-expanded destroyed")
}
