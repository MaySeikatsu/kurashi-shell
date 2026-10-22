import QtQuick
import "../core"

// Block (K42, K45): the one shape every chrome is made of, drawn from tokens only (rule 4: nothing here or in a caller
// compares the chrome's name). The four chromes are four sets of widths and colours:
//   outline  `Theme.outlineW` px in `Theme.outlineColor` (keycap ink, line chrome's outline role, soft chrome's faint
//            light rim; 0 under flat chrome, where `flatBorder` may still draw a hairline);
//   ring     `Theme.ringW` px in `Theme.ring` between outline and fill (keycap only), `ringScale` of it;
//   shadow   a hard one `Theme.shadowDy` px straight down in `Theme.line` (keycap), or a soft one — `Theme.softR` blur,
//            `Theme.softDy` down, `Theme.softColor` — under the face (soft chrome; `softScale` of it, 0 for none). The soft
//            shadow is one RectangularShadow, made only while the chrome has one: static, nothing runs per frame;
//   press    the face sinks onto its hard shadow and springs back with Theme.overshoot; or it shrinks to
//            `Theme.pressScale`; a chrome with neither (line) flashes its fill instead.
// Children land on the fill. The block's size includes the hard shadow: the face is `height - Theme.shadowDy` tall
// (`faceH`); centre content on `face` (anchors.centerIn: blk.face), not on the block.
// K59 (docs/ux/texture.md): a block with a fill of its own (`fill.a > 0`) carries the material's relief under its content,
// and over it with `Theme.texText`; the outline and the ring stay flat. A transparent block lies on the material beneath
// it, so the sheet is shaded once. `relief: false` for a picture (album art, a wallpaper thumbnail, an avatar) or a web page.
Item {
    id: blk
    property color fill: Theme.containerHigh
    property real radius: Theme.rLg
    property bool pressed: false
    // A hairline when the chrome has no outline of its own (flat cards, popups).
    property color flatBorder: "transparent"
    property bool animate: visible
    // K59: false for a picture (album art, a wallpaper thumbnail, an avatar) or a web page: the texture never shades it.
    property bool relief: true
    // Thinner keycap ring for small things (chips, bar pills): 0..1 of the token ring.
    property real ringScale: 1
    // How much of the soft shadow this block casts: 1 for a card or a key, less for small things inside other blocks.
    property real softScale: 1
    readonly property real ringW: Theme.ringW * ringScale
    readonly property real inset: Theme.outlineW + ringW
    readonly property real faceH: height - Theme.shadowDy
    readonly property alias face: face
    default property alias content: fillRect.data
    // The press a chrome has: a sink (hard shadow), a shrink (press scale), else a flash of the fill.
    readonly property bool flashes: Theme.shadowDy <= 0 && Theme.pressScale >= 1
    // The outline this block draws (0: none): the chrome's, else the flat hairline.
    readonly property real outlineWidth: Theme.outlineW > 0 ? Theme.outlineW : (flatBorder.a > 0 ? 1 : 0)
    readonly property color outlineInk: Theme.outlineW > 0 ? Theme.outlineColor : flatBorder

    implicitHeight: Theme.controlH + Theme.shadowDy

    Rectangle {
        visible: Theme.shadowDy > 0
        y: Theme.shadowDy
        width: blk.width
        height: blk.faceH
        radius: Math.min(blk.radius, height / 2)
        color: Theme.line
        antialiasing: true
    }
    Item {
        id: face
        width: blk.width
        height: blk.faceH
        y: blk.pressed ? Theme.shadowDy : 0
        scale: blk.pressed ? Theme.pressScale : 1
        Behavior on y {
            enabled: blk.animate && Theme.springOn
            NumberAnimation {
                duration: blk.pressed ? 70 : Theme.stdMs + 60
                easing.type: blk.pressed ? Easing.OutQuad : Easing.OutBack
                easing.overshoot: Theme.overshoot
            }
        }
        Behavior on scale {
            enabled: blk.animate && Theme.springOn
            NumberAnimation {
                duration: blk.pressed ? 80 : Theme.stdMs
                easing.type: blk.pressed ? Easing.OutQuad : Easing.OutBack
                easing.overshoot: Theme.overshoot
            }
        }
        // The soft shadow (soft chrome): made only while the theme has one and this block casts it.
        SoftShadow {
            anchors.fill: parent
            radius: blk.radius
            amount: blk.softScale
        }
        Rectangle {
            id: rim
            anchors.fill: parent
            radius: Math.min(blk.radius, height / 2)
            color: blk.ringW > 0 ? Theme.ring : blk.fill
            // A frame that draws the outline itself (kami's pen), or the pen (K62), replaces the straight line.
            border.width: frameHost.drawsOutline || pen.active ? 0 : blk.outlineWidth
            border.color: blk.outlineInk
            antialiasing: true
            Behavior on color { enabled: blk.animate && blk.ringW <= 0; ColorAnimation { duration: Theme.quickMs } }
        }
        // The press of a chrome without sink or shrink (line): the face lights at once and fades back on release (under
        // the content).
        Rectangle {
            anchors.fill: parent
            anchors.margins: Theme.outlineW
            radius: Math.max(0, Math.min(blk.radius, rim.height / 2) - Theme.outlineW)
            color: Theme.fg
            visible: blk.flashes && opacity > 0
            opacity: blk.pressed && blk.flashes ? 0.16 : 0
            Behavior on opacity {
                enabled: blk.animate && !blk.pressed
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutQuad }
            }
        }
        // K59: the material's relief over the fill and under the content (the outline and ring stay flat). A picture
        // or a web page opts out (`relief: false`); nothing is made while the theme has no shell texture.
        Loader {
            active: blk.relief && blk.fill.a > 0 && Theme.texShell && !Theme.texText
            anchors.fill: parent
            anchors.margins: blk.inset
            sourceComponent: Relief {
                anchors.fill: parent
                radius: Math.max(0, Math.min(blk.radius, face.height / 2) - blk.inset)
            }
        }
        Rectangle {
            id: fillRect
            anchors.fill: parent
            anchors.margins: blk.inset
            radius: Math.max(0, Math.min(blk.radius, rim.height / 2) - blk.inset)
            color: blk.ringW > 0 ? blk.fill : "transparent"
            antialiasing: true
            Behavior on color { enabled: blk.animate; ColorAnimation { duration: Theme.quickMs } }
            // K62: the pen's text modifiers draw the content (text, icons) through one layer while any is in effect;
            // not over a picture or a web page (`relief: false`).
            layer.enabled: Theme.penText && blk.relief
            layer.smooth: true
            layer.effect: PenInk {}
        }
        // With `texture.text` the relief is drawn over the content too: ink and icons sink into the same sheet.
        Loader {
            active: blk.relief && blk.fill.a > 0 && Theme.texShell && Theme.texText
            anchors.fill: parent
            anchors.margins: blk.inset
            sourceComponent: Relief {
                anchors.fill: parent
                radius: Math.max(0, Math.min(blk.radius, face.height / 2) - blk.inset)
            }
        }
        // K62: the pen draws the outline (a line style, fountain-pen modifiers) when one is in effect and the frame does
        // not draw its own; flat like the straight line it replaces. Nothing is made otherwise.
        Loader {
            id: pen
            active: Theme.penOutline && !frameHost.drawsOutline && blk.outlineWidth > 0
            anchors.fill: parent
            sourceComponent: PenOutline {
                radius: Math.min(blk.radius, rim.height / 2)
                color: blk.outlineInk
                lineWidth: blk.outlineWidth
            }
        }
        // The decor pack's frame over the face's edge (W25): nothing is made while the pack has none.
        FrameHost {
            id: frameHost
            anchors.fill: parent
            radius: Math.min(blk.radius, rim.height / 2)
            pressed: blk.pressed
            animate: blk.animate
        }
    }
}
