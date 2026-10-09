import QtQuick

// Test slot contribution (K28): one row in the clock's expanded footer.
Text {
    required property var store
    required property var theme
    required property var i18n
    text: "HELLO FOOTER"
    color: theme.dim
    font.pixelSize: theme.fsCaption
    Component.onCompleted: console.log("MODQML slot clock.expanded.footer created")
    Component.onDestruction: console.log("MODQML slot clock.expanded.footer destroyed")
}
