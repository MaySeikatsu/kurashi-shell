import QtQuick
import "../../../core"
import "../.."

// Keycap (W53.7, docs/ux/styles.md §9 sekai, K42): a menu in SekaiPop's keycap language — the chosen row is a key:
// one Block in the keycap chrome (the ink outline, the white ring, the hard shadow straight down it rests on), filled
// with the selection's tone, so a tray or dock menu reads like the launcher; it jumps from row to row (each row draws
// its own key). A separator is a line of ink dots, the dot field's. Roles only (rule 4); static.
MenuRowBase {
    id: row
    Loader {
        anchors.fill: parent
        anchors.leftMargin: 2
        anchors.rightMargin: 2
        active: row.highlighted && row.enabled && !row.separator
        sourceComponent: Block {
            fill: Theme.selected
            radius: Math.min(Theme.rLg, (height - Theme.shadowDy) / 2)
            animate: false
            relief: false
            penSeed: 0x5E7A
        }
    }
    Row {
        visible: row.separator
        anchors.centerIn: parent
        spacing: 6
        Repeater {
            model: row.separator ? Math.max(0, Math.floor((row.width - 24) / 10)) : 0
            Rectangle { width: 4; height: 4; radius: 2; color: Qt.alpha(Theme.line, 0.3) }
        }
    }
}
