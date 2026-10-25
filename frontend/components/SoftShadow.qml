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
    sourceComponent: RectangularShadow {
        offset.x: Theme.shadowX * sh.amount * sh.mirror
        offset.y: Theme.shadowY * sh.amount * sh.direction
        blur: Theme.softR * sh.amount
        spread: -1
        radius: Math.min(sh.radius, Math.min(width, height) / 2)
        color: Theme.softColor
    }
}
