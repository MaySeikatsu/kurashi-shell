import QtQuick
import "../../../core"

// CardSlot (W53.5, docs/ux/styles.md §8): the island as a memory-card slot of the PS2's browser — an original glyph, not
// the card's silhouette: a slim upright tile with rounded corners, a hairline in the silver ink, a fine rule across its
// upper third and a point of tower blue at its foot, standing at the pill's start; a blue glow line along the pill's foot.
// Every colour a role (rule 4); static.
IslandBase {
    id: cs
    radius: Theme.rSm
    lead: vertical ? 0 : Math.round(Theme.barH * 0.45)
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    Item {
        visible: !cs.vertical
        x: Math.round(Theme.pad * 0.8)
        width: Math.round(cs.height * 0.34)
        height: Math.round(cs.height * 0.5)
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
            anchors.fill: parent
            radius: Math.round(width * 0.24)
            color: Qt.alpha(Theme.accent, 0.14)
            border.width: cs.hair
            border.color: Qt.alpha(Theme.fg, 0.85)
        }
        Rectangle {
            x: Math.round(parent.width * 0.22); width: parent.width - 2 * x
            y: Math.round(parent.height * 0.3); height: cs.hair
            color: Qt.alpha(Theme.fg, 0.6)
        }
        Rectangle {
            width: Math.max(2, Math.round(parent.width * 0.28)); height: width; radius: width / 2
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Math.round(parent.height * 0.14) }
            color: Theme.accent
        }
    }
    Rectangle {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: cs.radius; rightMargin: cs.radius }
        height: cs.hair
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Theme.accent }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
}
