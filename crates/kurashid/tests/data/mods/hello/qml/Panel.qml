import QtQuick

// Test panel (K26): opened with `mod.panel.open {id: "hello", panel: "hello"}`.
Text {
    required property var store
    required property var theme
    required property var i18n
    text: "HELLO PANEL"
    color: theme.fg
    font.pixelSize: theme.fsTitle
    Component.onCompleted: console.log("MODQML panel created")
    Component.onDestruction: console.log("MODQML panel destroyed")
}
