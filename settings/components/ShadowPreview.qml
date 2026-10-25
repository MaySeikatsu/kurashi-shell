import QtQuick
import QtQuick.Effects
import "../core"

// Under Shadows (K67, docs/ux/shadows.md "Settings"): one block of the look in effect casting the shadow in effect — the
// daemon's `shadow.dx`/`shadow.dy`/`shadow.alpha_scale`, so it shows the strength, the direction and (following the
// light) the light's direction as they are, never a value that is not in effect (Shōjiki). The keycap's hard shadow, or
// the soft chrome's blurred one; a flat or line look draws no shadow, and the block shows that. Decorative: the rows
// beside it carry the numbers, so it is left out of the accessibility tree. Static: it changes only with the theme.
Item {
    id: sp
    readonly property real dx: Theme.tok("shadow.dx", 0)
    readonly property real dy: Theme.tok("shadow.dy", Theme.shadowDy + Theme.softDy)
    readonly property real alphaScale: Theme.tok("shadow.alpha_scale", 1)
    readonly property bool hard: Theme.shadowDy > 0
    readonly property bool soft: Theme.softR > 0 && sp.alphaScale > 0
    // Room for the longest shadow (strength 2, a low light: twice the look's, twice again) on every side.
    readonly property real room: 2 * Math.max(8, Theme.shadowDy * 2, Theme.softDy * 2 + Theme.softR)

    objectName: "shadow-preview"
    Accessible.ignored: true
    width: block.width + 2 * sp.room
    height: block.height + 2 * sp.room

    Rectangle {
        visible: sp.hard && (Math.round(sp.dx) !== 0 || Math.round(sp.dy) !== 0)
        x: block.x + Math.round(sp.dx)
        y: block.y + Math.round(sp.dy)
        width: block.width
        height: block.height
        radius: block.radius
        color: Theme.line
        antialiasing: true
    }
    Loader {
        x: block.x
        y: block.y
        width: block.width
        height: block.height
        active: sp.soft
        sourceComponent: RectangularShadow {
            offset.x: sp.dx
            offset.y: sp.dy
            blur: Theme.softR
            spread: -1
            radius: block.radius
            color: Qt.alpha(Theme.color("chrome.soft_color", "#000000"),
                Math.min(1, Theme.tok("chrome.soft_alpha", 0) * sp.alphaScale))
        }
    }
    Rectangle {
        id: block
        x: sp.room
        y: sp.room
        width: 120
        height: 48
        radius: Math.min(Theme.tok("radius.lg", 18), height / 2)
        color: Theme.ringW > 0 ? Theme.ring : Theme.color("color.surface_container_high", "#2f2c33")
        border.width: Theme.outlineW
        border.color: Theme.outlineColor
        antialiasing: true
        Rectangle {
            visible: Theme.ringW > 0
            anchors.fill: parent
            anchors.margins: Theme.outlineW + Theme.ringW
            radius: Math.max(0, parent.radius - anchors.margins)
            color: Theme.color("color.surface_container_high", "#2f2c33")
        }
    }
}
