import QtQuick
import "../../../core"
import ".."

// Classic (W53.1): a bevel-era push button's face — raised (white and light over shadow and black), sunk while pressed; a
// checked (latched) button sunk on a checker of face and highlight, as 9x's toolbar toggles; the default (`primary`)
// framed in 1 px of black. The caller's content sits on it and moves 1 px down-right while pressed. Static.
ButtonBase {
    id: bf
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    Rectangle { anchors.fill: parent; color: bf.primary ? Theme.bevelDark : Theme.surface }
    Item {
        anchors.fill: parent
        anchors.margins: bf.primary ? bf.hair : 0
        Rectangle { anchors.fill: parent; color: Theme.surface }
        Loader {
            anchors.fill: parent
            anchors.margins: 2 * bf.hair
            active: bf.checked && !bf.pressed
            sourceComponent: Checker {}
        }
        BevelEdge { anchors.fill: parent; w: bf.hair; sunk: bf.pressed || bf.checked }
    }
}
