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
    // I427: part of the sheet (a bar, a sidebar, the dock): its shadow is `theme.material.sheet_shadow`'s, Inward among them:
    // evenly all round, with no direction (Caelestia's). Otherwise the surfaces' elevation.
    property bool sheet: false
    readonly property string mode: sheet ? Theme.sheetMode : Theme.elevationMode
    readonly property bool inward: mode === "inward"
    readonly property var dirRest: sheet ? Theme.sheetDir : Theme.elevationDir
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
    active: mode !== "off" && Theme.elevationStrength > 0 && level > 0 && width > 0 && height > 0

    // [ambient blur, ambient alpha, key distance, key blur, key alpha] per level (starting values, tuned on niri).
    readonly property var ladder: [[0, 0, 0, 0, 0], [12, 0.12, 2, 6, 0.18], [26, 0.18, 6, 14, 0.24],
        [34, 0.20, 10, 20, 0.26], [46, 0.22, 14, 26, 0.28]]
    // (Inward: only the all-round layer, as far as the key would have reached, darker.)
    readonly property var l: {
        var v = ladder[Math.max(0, Math.min(4, level))]
        return inward ? [v[3] * 1.6, 0.5, 0, v[3], 0] : v
    }
    readonly property real s: Theme.elevationStrength
    readonly property real dark: Theme.darkScheme ? 1.6 : 1
    readonly property color ink: Qt.rgba(Theme.line.r * 0.4, Theme.line.g * 0.4, Theme.line.b * 0.4, 1)
    // The surface lets what lies under it show (a translucent material): its shadow must not (W53.4).
    readonly property bool hollow: Theme.tok("color.surface_alpha", 1) < 0.999

    // The pointer's lamp on this output turns the key layer away from it (where it stands relative to the shape).
    readonly property var qsw: QsWindow.window
    readonly property bool lamp: mode === "follow" && Theme.elevationPointer && Light.wanted && Light.k > 0 && !!qsw && !!qsw.screen
        && Light.output === qsw.screen.name
    // The lamp held on this output (the wallpaper's light, the spotlight's pin: Light.heldLamp) under follow: the shadow
    // falls away from it here, its length from how low it stands (I338: the relief's light and the shadows are one).
    readonly property point held: {
        var h = mode === "follow" ? Light.heldLamp(qsw) : null
        return h ? h : Qt.point(-1e9, -1e9)
    }
    readonly property bool pinned: held.x > -1e8
    readonly property point centre: {
        if (!lamp && !pinned) return Qt.point(0, 0)
        var o = Light.originOf(qsw), p = el.mapToItem(null, el.width / 2, el.height / 2)
        return Qt.point(o.x + p.x, o.y + p.y)
    }
    readonly property var want: lamp ? Light.awayFrom(Light.x, Light.y, centre.x, centre.y, el.dirRest)
        : pinned ? Light.awayFrom(held.x, held.y, centre.x, centre.y, el.dirRest) : el.dirRest
    readonly property real wantX: want[0]
    readonly property real wantY: want[1]
    // The key's length factor (the daemon's for a directional light, the lamp's height here for a held or pointer lamp).
    readonly property real len: want[2]
    property real ux: wantX
    property real uy: wantY
    Behavior on ux { enabled: el.lamp && el.visible && Theme.springOn; NumberAnimation { duration: Theme.longMs; easing.type: Easing.OutCubic } }
    Behavior on uy { enabled: el.lamp && el.visible && Theme.springOn; NumberAnimation { duration: Theme.longMs; easing.type: Easing.OutCubic } }

    // How far the shadow reaches past the shape (blur and the key's offset): the clip's margin on uncut sides.
    readonly property real reach: Math.max(l[0] * s, l[2] * 2 * s + l[3] * Math.max(0.5, s)) + 2
    // (The loaded root fills the Loader — a Loader of explicit size resizes its item to itself — so the clip box is a child
    // that keeps its own size: it reaches `reach` past every side that is not cut. I338: the root itself as the clip box
    // was resized to the shape, so a cut shadow was also cut at the shape's other sides.)
    sourceComponent: Item {
      Item {
        x: el.cutLeft ? 0 : -el.reach
        y: el.cutTop ? 0 : -el.reach
        width: el.width + (el.cutLeft ? 0 : el.reach) + (el.cutRight ? 0 : el.reach)
        height: el.height + (el.cutTop ? 0 : el.reach) + (el.cutBottom ? 0 : el.reach)
        clip: el.cutLeft || el.cutRight || el.cutTop || el.cutBottom
        // W53.4 (contract row 608): under a translucent material the shadow showed through the surface — its offset key
        // layer left a lighter band along one side of every glass card (vibrancy, glass, aero). There the shadow is drawn
        // through one layer with the shape's own rounded box knocked out, so it falls only outside; made only then
        // (one paint per size, nothing per frame). Solid looks keep the two analytic layers alone.
        layer.enabled: el.hollow
        layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskSource: knock
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.5
        }
        Item {
            id: knock
            anchors.fill: parent
            visible: false
            layer.enabled: el.hollow
            Rectangle {
                x: shape.x
                y: shape.y
                width: shape.width
                height: shape.height
                radius: Math.min(el.radius, Math.min(width, height) / 2)
                color: "white"
            }
        }
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
            offset.x: el.ux * el.mirrorX * el.l[2] * el.len * el.s
            offset.y: el.uy * el.mirrorY * el.l[2] * el.len * el.s
            blur: el.l[3] * Math.max(0.5, el.s)
            spread: -1
            color: Qt.alpha(el.ink, Math.min(0.9, el.l[4] * el.s * el.dark))
        }
        }
    }
      }
}
