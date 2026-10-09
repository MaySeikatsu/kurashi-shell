import QtQuick

// Test slot contribution (K28): listed with ready=false by the stand-in, so it must never be instantiated.
Text {
    required property var store
    required property var theme
    required property var i18n
    text: "HELLO DAY (NOT READY)"
    Component.onCompleted: console.log("MODQML slot clock.expanded.day created")
    Component.onDestruction: console.log("MODQML slot clock.expanded.day destroyed")
}
