import QtQuick
import "../core"
import "decor"

// A menu's card where it is drawn inside another window (W82: a web page's menu in the web host): the Stage card's own
// chrome for the look as a card apart — its elevation (level 3), corners, outline or pen, banded fill and frame, wash,
// material and pattern — so the menu reads as the shell's, not as a plain box. Opaque: nothing blurs behind it there.
// Children go into the card (clipped to it).
Item {
    id: mc
    default property alias content: card.data
    readonly property alias radius: card.radius

    Elevation {
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        radius: card.radius
        level: 3
    }
    RoundBox {
        id: card
        anchors.fill: parent
        sheet: true
        clip: true
        radius: Theme.rLg
        color: Qt.alpha(Theme.surface, 1)
        // (with a pen in effect the pen draws the outline, as on the Stage's card)
        border.width: pen.active ? 0 : Theme.surfaceLineW
        border.color: Theme.surfaceLineColor
        Loader {
            id: pen
            z: 5
            anchors.fill: parent
            active: Theme.penOutline
            sourceComponent: PenOutline { radius: card.radius; inset: 1; color: Theme.surfaceLineColor; lineWidth: Theme.surfaceLineW; seed: 0x57A6E }
        }
        Loader {
            anchors.fill: parent
            active: Theme.frame !== "" || Theme.fillBands > 1
            sourceComponent: PanelDress { radius: card.radius; alpha: 1; shaped: card.cornerJoin !== "" }
        }
        Loader {
            anchors.fill: parent
            anchors.margins: Theme.outlineW
            active: Theme.washOn
            sourceComponent: Wash { anchors.fill: parent; radius: Math.max(0, card.radius - Theme.outlineW); fill: Qt.alpha(Theme.panel, 1); strength: 1 }
        }
        Loader {
            anchors.fill: parent
            anchors.margins: Theme.outlineW
            active: Theme.texShell
            sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, card.radius - Theme.outlineW) }
        }
        Loader {
            anchors.fill: parent
            anchors.margins: Theme.outlineW
            active: Theme.decor("pattern.kind", "none") !== "none" && Theme.decor("pattern.strength", 0) > 0
            sourceComponent: Pattern { radius: card.radius }
        }
    }
}
