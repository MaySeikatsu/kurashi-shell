import QtQuick
import QtQuick.Effects
import "../core"
import "decor"

// Block (K42, K45): the one shape every chrome is made of, drawn from tokens only (rule 4: nothing here or in a caller
// compares the chrome's name). The four chromes are four sets of widths and colours:
//   outline  `Theme.outlineW` px in `Theme.outlineColor` (keycap ink, line chrome's outline role, soft chrome's faint
//            light rim; 0 under flat chrome, where `flatBorder` may still draw a hairline);
//   ring     `Theme.ringW` px in `Theme.ring` between outline and fill (keycap only), `ringScale` of it;
//   shadow   a hard one in `Theme.line` along the shadow vector `Theme.sinkX/Y` (keycap; K67: the user's strength and
//            direction, `Theme.shadowDy` straight down by default), or a soft one — `Theme.softR` blur, offset along
//            `Theme.shadowX/Y`, `Theme.softColor` — under the face (soft chrome; `softScale` of it, 0 for none). The soft
//            shadow is one RectangularShadow, made only while the chrome has one: static, nothing runs per frame;
//   press    the face sinks onto its hard shadow, along the vector, and springs back with Theme.overshoot; or it shrinks
//            to `Theme.pressScale`; a chrome with neither (line, a keycap at strength 0) flashes its fill instead.
// Children land on the fill. The block's size includes the hard shadow: the face is `height - Theme.shadowDy` tall
// (`faceH`); centre content on `face` (anchors.centerIn: blk.face), not on the block.
// K59 (docs/ux/texture.md): a block with a fill of its own (`fill.a > 0`) carries the material's relief under its content,
// and over it with `Theme.texText`; the outline and the ring stay flat. A transparent block lies on the material beneath
// it, so the sheet is shaded once. `relief: false` for a picture (album art, a wallpaper thumbnail, an avatar) or a web page.
// W39 (I199, I204): a Block is in every key, tile and card, so it is kept light — a quick card makes ~30, a month grid 42.
// What only some looks draw (the press flash, the reliefs, the pen's outline, the decor frame) is made by two Loaders, one
// under the content and one over it, only while the look has any of it; the sink and the shrink share one eased value and
// the fill one colour animation (two Behaviors, not five). The stacking order is the same as before, so every chrome
// draws what it drew (tools/bench/block-identity.sh).
// W53.0a (K80): the bevel chrome — `Theme.bevelW` px light/dark pairs over the face's edge (decor/BevelEdge.qml), the
// pairs swapped while pressed or `sunken` (a text field, the tray well), the content moved `Theme.bevelPress` px down
// and right while pressed (no sink, no shrink, no flash); and the materials next to blur — a glow and a bloom under the
// face, a sheen on its upper half — each made only while the look has it (0 frames idle).
Item {
    id: blk
    property color fill: Theme.containerHigh
    property real radius: Theme.rLg
    property bool pressed: false
    // A well (K80): drawn pressed in at rest — the bevel's pairs swapped. Only a bevel look draws it.
    property bool sunken: false
    // W53.4 (row 604): a look's part draws this block's face (a push button's `[slots] button`): no fill, outline, shadow,
    // glow, press motion or frame of its own — only the content.
    property bool bare: false
    // A hairline when the chrome has no outline of its own (flat cards, popups).
    property color flatBorder: "transparent"
    property bool animate: visible
    // K59: false for a picture (album art, a wallpaper thumbnail, an avatar) or a web page: the texture never shades it.
    property bool relief: true
    // Thinner keycap ring for small things (chips, bar pills): 0..1 of the token ring.
    property real ringScale: 1
    // How much of the soft shadow this block casts: 1 for a card or a key, less for small things inside other blocks.
    property real softScale: 1
    // K62: the pen's salt for this block's outline (≥ 0); -1 = the block's place in its parent (pen.js `salt`).
    property int penSeed: -1
    readonly property real ringW: Theme.ringW * ringScale
    // The content sits inside the outline, the ring and both bevel pairs.
    readonly property real inset: Theme.outlineW + ringW + 2 * Theme.bevelW
    readonly property real faceH: height - Theme.shadowDy
    readonly property alias face: face
    default property alias content: fillRect.data
    // The press a chrome has: a sink (hard shadow), a shrink (press scale), a bevel's swap, else a flash of the fill (also
    // a keycap whose shadow is set to nothing: K67, nothing to sink onto).
    readonly property bool flashes: Theme.sinkX === 0 && Theme.sinkY === 0 && Theme.pressScale >= 1 && Theme.bevelW === 0
    // How far the content moves down and right while pressed (a bevel's press; 0 for every other chrome).
    readonly property int shift: pressed ? Theme.bevelPress : 0
    // The outline this block draws (0: none): the chrome's, else the flat hairline.
    readonly property real outlineWidth: Theme.outlineW > 0 ? Theme.outlineW : (flatBorder.a > 0 ? 1 : 0)
    readonly property color outlineInk: Theme.outlineW > 0 ? Theme.outlineColor : flatBorder
    // I281: a squircle look draws the shadow, the rim and the ring's fill as squircles (SquircleRect, made only then);
    // a pill (its corner half the face or more) stays round.
    readonly property bool sq: Theme.squircle > 0 && Math.min(blk.radius, blk.faceH / 2) < Math.min(blk.width, blk.faceH) / 2 - 0.5

    implicitHeight: Theme.controlH + Theme.shadowDy

    // The hard shadow along the shadow vector (K67: `Theme.sinkX/Y`, straight down by `Theme.shadowDy` by default). The
    // block keeps `Theme.shadowDy` of room below its face whatever the vector; a longer or sideways shadow reaches past it.
    Rectangle {
        visible: (Theme.sinkX !== 0 || Theme.sinkY !== 0) && !blk.bare
        x: Theme.sinkX
        y: Theme.sinkY
        width: blk.width
        height: blk.faceH
        radius: face.r
        color: blk.sq ? "transparent" : Theme.line
        antialiasing: true
        Loader {
            anchors.fill: parent
            active: blk.sq
            sourceComponent: SquircleRect { radius: face.r; color: Theme.line }
        }
    }
    Item {
        id: face
        // The face's corner, and the fill's inside the outline and the ring.
        readonly property real r: Math.min(blk.radius, blk.faceH / 2)
        readonly property real innerR: Math.max(0, r - blk.inset)
        // The fill as drawn: it follows `fill` through one colour animation (the ring's colour never animates).
        property color shownFill: blk.fill
        Behavior on shownFill { enabled: blk.animate; ColorAnimation { duration: Theme.quickMs } }
        // 0 at rest, 1 pressed: the sink along the vector and the shrink to the press scale, one eased value (a chrome
        // has one or the other). At the ends it is exactly what it stands for, so a block at rest or held is unchanged.
        property real pressP: blk.pressed ? 1 : 0
        readonly property bool shrinks: Theme.sinkX === 0 && Theme.sinkY === 0
        Behavior on pressP {
            enabled: blk.animate && Theme.springOn
            NumberAnimation {
                duration: blk.pressed ? (face.shrinks ? 80 : 70) : (face.shrinks ? Theme.stdMs : Theme.stdMs + 60)
                easing.type: blk.pressed ? Easing.OutQuad : Easing.OutBack
                easing.overshoot: Theme.overshoot
            }
        }
        width: blk.width
        height: blk.faceH
        // The press sinks the face onto its shadow, along the vector.
        x: blk.bare ? 0 : Theme.sinkX * pressP
        y: blk.bare ? 0 : Theme.sinkY * pressP
        scale: blk.bare ? 1 : 1 - (1 - Theme.pressScale) * pressP
        // W53.0a: the glow (a role's colour) and the bloom (the face's own, lighter) round the face: two static halos, made
        // only while the look has either; small things inside blocks glow as little as they cast shadows (`softScale`).
        Loader {
            z: -1
            anchors.fill: parent
            active: (Theme.glow > 0 || Theme.bloom > 0) && blk.softScale > 0 && !blk.bare
            sourceComponent: Item {
                RectangularShadow {
                    anchors.fill: parent
                    visible: Theme.glow > 0
                    blur: Theme.glowR * blk.softScale
                    spread: 0
                    radius: Math.min(face.r, Math.min(width, height) / 2)
                    color: Qt.alpha(Theme.glowColor, Theme.glow)
                }
                RectangularShadow {
                    anchors.fill: parent
                    visible: Theme.bloom > 0
                    blur: Theme.bloomR * blk.softScale
                    spread: 2
                    radius: Math.min(face.r, Math.min(width, height) / 2)
                    color: Qt.alpha(Qt.lighter(face.shownFill, 1.6), Theme.bloom)
                }
            }
        }
        // The soft shadow (soft chrome): made only while the theme has one and this block casts it.
        SoftShadow {
            anchors.fill: parent
            radius: blk.radius
            amount: blk.bare ? 0 : blk.softScale
        }
        Rectangle {
            id: rim
            anchors.fill: parent
            radius: face.r
            readonly property color fillC: blk.ringW > 0 ? Theme.ring : face.shownFill
            // A frame that draws the outline itself (kami's pen), or the pen (K62), replaces the straight line.
            readonly property real lineW: over.item !== null && over.item.hidesOutline ? 0 : blk.outlineWidth
            visible: !blk.bare
            color: blk.sq ? "transparent" : fillC
            border.width: blk.sq ? 0 : lineW
            border.color: blk.outlineInk
            antialiasing: true
            Loader {
                anchors.fill: parent
                active: blk.sq
                sourceComponent: SquircleRect {
                    radius: face.r
                    color: rim.fillC
                    borderWidth: rim.lineW
                    borderColor: blk.outlineInk
                }
            }
        }
        // Under the content: the press flash of a chrome without sink or shrink (line), and the material's relief (K59).
        Loader {
            id: under
            readonly property bool relief: blk.relief && blk.fill.a > 0 && Theme.texShell && !Theme.texText
            readonly property bool sheen: Theme.sheen > 0 && blk.fill.a > 0
            // W53.4: the look's ground pattern (Aqua's pinstripes) on a window-sized block with a fill of its own (cards,
            // panels, menus; ≥ 120 × 64 as a frame's card kind), never on keys and tiles.
            readonly property bool pattern: blk.fill.a > 0 && blk.width >= 120 && blk.faceH >= 64
                && Theme.decor("pattern.kind", "none") !== "none" && Theme.decor("pattern.strength", 0) > 0
            active: !blk.bare && (blk.flashes || relief || sheen || pattern)
            anchors.fill: parent
            sourceComponent: Item {
                Loader {
                    active: under.pattern
                    anchors.fill: parent
                    anchors.margins: blk.inset
                    sourceComponent: Pattern { radius: face.innerR }
                }
                // W53.0a: the sheen (Vista/7 glass buttons): a light gloss over the upper half of the fill, fading out.
                Rectangle {
                    visible: under.sheen
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: blk.inset }
                    height: (parent.height - 2 * blk.inset) / 2
                    radius: face.innerR
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.5 * Theme.sheen) }
                        GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.12 * Theme.sheen) }
                    }
                }
                // The flash: the face lights at once and fades back on release.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: Theme.outlineW
                    radius: Math.max(0, face.r - Theme.outlineW)
                    color: Theme.fg
                    visible: blk.flashes && opacity > 0
                    opacity: blk.pressed && blk.flashes ? 0.16 : 0
                    Behavior on opacity {
                        enabled: blk.animate && !blk.pressed
                        NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutQuad }
                    }
                }
                // K59: the relief over the fill and under the content (the outline and ring stay flat). A picture or a
                // web page opts out (`relief: false`); nothing is made while the theme has no shell texture.
                Loader {
                    active: under.relief
                    anchors.fill: parent
                    anchors.margins: blk.inset
                    sourceComponent: Relief {
                        anchors.fill: parent
                        radius: face.innerR
                    }
                }
            }
        }
        Rectangle {
            id: fillRect
            anchors.fill: parent
            anchors.margins: blk.inset
            // A bevel's press moves the content (0 otherwise: the margins are the inset).
            anchors.topMargin: blk.inset + blk.shift
            anchors.leftMargin: blk.inset + blk.shift
            anchors.bottomMargin: blk.inset - blk.shift
            anchors.rightMargin: blk.inset - blk.shift
            radius: face.innerR
            color: blk.ringW > 0 && !blk.sq && !blk.bare ? face.shownFill : "transparent"
            antialiasing: true
            Loader {
                z: -1
                anchors.fill: parent
                active: blk.sq && blk.ringW > 0 && !blk.bare
                sourceComponent: SquircleRect { radius: face.innerR; color: face.shownFill }
            }
            // K62: the pen's text modifiers draw the content (text, icons) through one layer while any is in effect;
            // not over a picture or a web page (`relief: false`).
            layer.enabled: Theme.penText && blk.relief
            layer.smooth: true
            layer.effect: PenInk {
                anchor: blk
                seed: blk.penSeed
            }
        }
        // Over the content: the relief with `texture.text`, the pen's outline (K62) and the decor pack's frame (W25).
        Loader {
            id: over
            readonly property bool relief: blk.relief && blk.fill.a > 0 && Theme.texShell && Theme.texText
            active: !blk.bare && (relief || Theme.frame !== "" || (Theme.penOutline && blk.outlineWidth > 0) || Theme.bevelW > 0)
            anchors.fill: parent
            sourceComponent: Item {
                // The frame or the pen draws the outline: the rim leaves its straight line out.
                readonly property bool hidesOutline: frameHost.drawsOutline || pen.active
                // W53.0a (K80): the bevel's two pairs over the face's edge, swapped while pressed or sunken.
                Loader {
                    active: Theme.bevelW > 0
                    anchors.fill: parent
                    sourceComponent: BevelEdge {
                        sunk: blk.pressed || blk.sunken
                    }
                }
                // With `texture.text` the relief is drawn over the content too: ink and icons sink into the same sheet.
                Loader {
                    active: over.relief
                    anchors.fill: parent
                    anchors.margins: blk.inset
                    sourceComponent: Relief {
                        anchors.fill: parent
                        radius: face.innerR
                    }
                }
                // The pen draws the outline (a line style, fountain-pen modifiers) when one is in effect and the frame
                // does not draw its own; flat like the straight line it replaces.
                Loader {
                    id: pen
                    active: Theme.penOutline && !frameHost.drawsOutline && blk.outlineWidth > 0
                    anchors.fill: parent
                    sourceComponent: PenOutline {
                        radius: face.r
                        color: blk.outlineInk
                        lineWidth: blk.outlineWidth
                        seed: blk.penSeed
                        anchor: blk
                    }
                }
                // The decor pack's frame over the face's edge: nothing is made while the pack has none.
                FrameHost {
                    id: frameHost
                    anchors.fill: parent
                    radius: face.r
                    pressed: blk.pressed
                    animate: blk.animate
                    anchor: blk
                    penSeed: blk.penSeed
                }
            }
        }
    }
}
