import QtQuick
import qs.components.quick

// Test slot contribution (K28, W18): the test mod's tile in the quick settings card. A QuickTile, so it has the core tiles'
// size and look. It has no switch and no page: the main zone does nothing, and the keys reach it like any tile's.
QuickTile {
    required property var store
    required property var theme
    required property var i18n
    glyph: "◉"
    label: "Hello"
    subtitle: "Test tile"
    toggles: false
    hasPage: false
    Component.onCompleted: console.log("MODQML slot quick.tiles created")
    Component.onDestruction: console.log("MODQML slot quick.tiles destroyed")
}
