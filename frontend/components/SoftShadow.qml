import QtQuick
import QtQuick.Effects
import "../core"

// The soft chrome's drop shadow (K45; Vitreus, pleamar): `Theme.softR` blur, `Theme.softDy` down, `Theme.softColor`,
// `amount` of it. Fill it over the shape it shades (anchors.fill) and give it that shape's radius; as a child with the
// default z of -1 it draws below its parent. Made only while the theme has a soft shadow (every other chrome: nothing),
// and it is static: one RectangularShadow, no layer, nothing per frame (Ma).
Loader {
    id: sh
    property real radius: 0
    property real amount: 1
    // -1 casts it upwards (a shape drawn mirrored, under a bottom bar).
    property real direction: 1
    z: -1
    active: Theme.softR > 0 && amount > 0
    sourceComponent: RectangularShadow {
        offset.y: Theme.softDy * sh.amount * sh.direction
        blur: Theme.softR * sh.amount
        spread: -1
        radius: Math.min(sh.radius, Math.min(width, height) / 2)
        color: Theme.softColor
    }
}
