import QtQuick

// Test slot contribution (K28): a 140 x 60 box beside the date in the clock view.
Rectangle {
    required property var store
    required property var theme
    required property var i18n
    implicitWidth: 140
    implicitHeight: 60
    radius: 6
    color: theme.accent
    Text { anchors.centerIn: parent; text: "HELLO ASIDE"; color: theme.fgOnAccent; font.pixelSize: theme.fsCaption }
    Component.onCompleted: console.log("MODQML slot clock.expanded.aside created")
    Component.onDestruction: console.log("MODQML slot clock.expanded.aside destroyed")
}
