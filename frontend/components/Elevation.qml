import QtQuick
import QtQuick.Effects
import Quickshell
import "../core"

// W57 (K78, docs/ux/shadows.md "Elevation"): a surface's smooth drop shadow, lifting it off the desktop — two analytic
// layers (RectangularShadow: no blur passes, no layer): a wide faint ambient one all round and a softer key one along the
// light (`Theme.elevationDir`: the shadow direction, or away from the light under follow, longer when it stands low).
// Fill it over the shape (anchors.fill), give it the shape's radius and its `level` (1 frame and docked bars, 2 dock,
// sidebars, floating bars, 3 cards and popups, 4 toasts, launcher, OSD, polkit); as a child with z −1 it draws below.
// Made only while elevation is on. With `elevation.pointer` and the pointer's lamp on this output it turns away from the
// lamp, eased over `motion.long` (off under reduced motion: the daemon drops the setting); at rest nothing runs (Ma).
Loader {
    id: el
    property int level: 2
    property real radius: 0
    // Sides joined to a neighbour (a column's fillets on the band, its outer side on the screen's edge): the shadow is
    // cut there, so joined shapes read as one sheet (K78) — it only falls where the surface meets the desktop.
    property bool cutTop: false
    property bool cutBottom: false
    property bool cutLeft: false
    property bool cutRight: false
    // −1 inside a frame mirrored that way (ColumnShape's flips): the key still falls the screen's way.
    property real mirrorX: 1
    property real mirrorY: 1
    // The window's room for the shadow is the owner's: the shadow is drawn where the item lies, never past its window.
    z: -1
    active: Theme.elevationMode !== "off" && Theme.elevationStrength > 0 && level > 0 && width > 0 && height > 0

    // [ambient blur, ambient alpha, key distance, key blur, key alpha] per level (starting values, tuned on niri).
    readonly property var ladder: [[0, 0, 0, 0, 0], [12, 0.12, 2, 6, 0.18], [26, 0.18, 6, 14, 0.24],
        [34, 0.20, 10, 20, 0.26], [46, 0.22, 14, 26, 0.28]]
    readonly property var l: ladder[Math.max(0, Math.min(4, level))]
    readonly property real s: Theme.elevationStrength
    readonly property real dark: Theme.darkScheme ? 1.6 : 1
    readonly property color ink: Qt.rgba(Theme.line.r * 0.4, Theme.line.g * 0.4, Theme.line.b * 0.4, 1)

    // The pointer's lamp on this output turns the key layer away from it (where it stands relative to the shape).
    readonly property var qsw: QsWindow.window
    readonly property bool lamp: Theme.elevationPointer && Light.wanted && Light.k > 0 && !!qsw && !!qsw.screen
        && Light.output === qsw.screen.name
    readonly property point centre: {
        if (!lamp) return Qt.point(0, 0)
        var o = Light.originOf(qsw), p = el.mapToItem(null, el.width / 2, el.height / 2)
        return Qt.point(o.x + p.x, o.y + p.y)
    }
    readonly property real wantX: {
        if (!lamp) return Theme.elevationDir[0]
        var dx = centre.x - Light.x, dy = centre.y - Light.y, n = Math.hypot(dx, dy)
        return n < 1 ? Theme.elevationDir[0] : dx / n
    }
    readonly property real wantY: {
        if (!lamp) return Theme.elevationDir[1]
        var dx = centre.x - Light.x, dy = centre.y - Light.y, n = Math.hypot(dx, dy)
        return n < 1 ? Theme.elevationDir[1] : dy / n
    }
    property real ux: wantX
    property real uy: wantY
    Behavior on ux { enabled: el.lamp && el.visible && Theme.springOn; NumberAnimation { duration: Theme.longMs; easing.type: Easing.OutCubic } }
    Behavior on uy { enabled: el.lamp && el.visible && Theme.springOn; NumberAnimation { duration: Theme.longMs; easing.type: Easing.OutCubic } }

    // How far the shadow reaches past the shape (blur and the key's offset): the clip's margin on uncut sides.
    readonly property real reach: Math.max(l[0] * s, l[2] * Theme.elevationDir[2] * s + l[3] * Math.max(0.5, s)) + 2
    sourceComponent: Item {
        x: el.cutLeft ? 0 : -el.reach
        y: el.cutTop ? 0 : -el.reach
        width: el.width + (el.cutLeft ? 0 : el.reach) + (el.cutRight ? 0 : el.reach)
        height: el.height + (el.cutTop ? 0 : el.reach) + (el.cutBottom ? 0 : el.reach)
        clip: el.cutLeft || el.cutRight || el.cutTop || el.cutBottom
        Item {
            id: shape
            x: el.cutLeft ? 0 : el.reach
            y: el.cutTop ? 0 : el.reach
            width: el.width
            height: el.height
        RectangularShadow {
            anchors.fill: parent
            radius: Math.min(el.radius, Math.min(width, height) / 2)
            blur: el.l[0] * el.s
            spread: 0
            color: Qt.alpha(el.ink, Math.min(0.9, el.l[1] * el.s * el.dark))
        }
        RectangularShadow {
            anchors.fill: parent
            radius: Math.min(el.radius, Math.min(width, height) / 2)
            offset.x: el.ux * el.mirrorX * el.l[2] * Theme.elevationDir[2] * el.s
            offset.y: el.uy * el.mirrorY * el.l[2] * Theme.elevationDir[2] * el.s
            blur: el.l[3] * Math.max(0.5, el.s)
            spread: -1
            color: Qt.alpha(el.ink, Math.min(0.9, el.l[4] * el.s * el.dark))
        }
        }
    }
}
