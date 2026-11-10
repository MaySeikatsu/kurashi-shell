import QtQuick
import QtQuick.Effects
import "../core"

// The soft chrome's drop shadow (K45; Vitreus, pleamar): `Theme.softR` blur, offset along the shadow vector
// (`Theme.shadowX/Y`, K67: the look's `softDy` straight down by default), `Theme.softColor`, `amount` of it. Fill it over
// the shape it shades (anchors.fill) and give it that shape's radius; as a child with the default z of -1 it draws below
// its parent. Made only while the theme has a soft shadow (every other chrome, and strength 0: nothing), and it is
// static: one RectangularShadow, no layer, nothing per frame (Ma); a new direction (a daytime light) moves it once.
Loader {
    id: sh
    property real radius: 0
    property real amount: 1
    // -1 inside a frame mirrored vertically (a shape drawn under a bottom bar): the shadow still falls the screen's way.
    property real direction: 1
    // -1 inside a frame mirrored horizontally (a left sidebar drawn in a right one's frame).
    property real mirror: 1
    z: -1
    active: Theme.softR > 0 && amount > 0 && Theme.shadowAlpha > 0
    // B79: a chrome whose soft shadow is light (`chrome.soft_glow`, the Glow chrome) draws a glowing ring instead: the
    // tube on the edge and its light out over the ground and a little way in, also under a see-through fill (light shows
    // through glass). Small things glow at least `chrome.soft_glow_min` of it: a bar's group is lit as a card is.
    sourceComponent: Theme.softGlow ? ring : shadow
    Component {
        id: ring
        Item {
            readonly property real amt: Math.max(sh.amount, Theme.softGlowMin)
            readonly property real reach: Theme.softR * amt * 1.6
            readonly property real pad: Math.ceil(reach) + 2
            ShaderEffect {
                x: -parent.pad
                y: -parent.pad
                width: parent.width + 2 * parent.pad
                height: parent.height + 2 * parent.pad
                readonly property vector4d uGeo: Qt.vector4d(width, height, parent.pad, Math.min(sh.radius, Math.min(parent.width, parent.height) / 2))
                readonly property color uColor: Qt.alpha(Theme.softColor, 1)
                readonly property vector4d uLight: Qt.vector4d(parent.reach, Math.min(parent.reach * 0.55, Math.min(parent.width, parent.height) / 2),
                    Theme.softColor.a, Math.max(1, Theme.outlineW))
                fragmentShader: Qt.resolvedUrl("../shaders/glow_ring.frag.qsb")
            }
        }
    }
    Component {
        id: shadow
        RectangularShadow {
        offset.x: Theme.shadowX * sh.amount * sh.mirror
        offset.y: Theme.shadowY * sh.amount * sh.direction
        blur: Theme.softR * sh.amount
        spread: -1
        radius: Math.min(sh.radius, Math.min(width, height) / 2)
        color: Theme.softColor
    }
    }
}
