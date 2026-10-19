import QtQuick

// Test day mark (K28 slot `clock.expanded.daymark`, row 71): a dot under the number of one fixed date, 2026-10-14, so the
// month grid's marks are tested without the weather mod. The host gives `date` (yyyy-mm-dd) on each load; the dot takes no
// room on any other day.
Item {
    id: mark
    required property var store
    required property var theme
    required property var i18n
    property string date: ""
    readonly property bool dotted: date === "2026-10-14"
    implicitWidth: dotted ? 14 : 0
    implicitHeight: 14
    Rectangle {
        anchors.centerIn: parent
        width: 6
        height: 6
        radius: 3
        color: theme.accent
        visible: mark.dotted
    }
    Component.onCompleted: console.log("MODQML slot clock.expanded.daymark created")
    Component.onDestruction: console.log("MODQML slot clock.expanded.daymark destroyed")
}
