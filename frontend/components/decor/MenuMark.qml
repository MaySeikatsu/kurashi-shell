import QtQuick
import QtQuick.Shapes

// MenuMark (W53.4): the original mark a menu-bar dress shows where Mac OS X and macOS have Apple's logo — never that
// logo. 暮 (kurashi's "dusk"): a sun setting behind the horizon, a disc whose lower part breaks into two bands, readable
// at 14 px. `color` fills it; with `gloss` > 0 it is a gel (Jaguar's blue mark: a light top falling to the colour, a
// darker foot, a white highlight on the cap), at 0 a flat glyph (macOS 11+). Any part may use it (the start dress, the
// login window's header). Static: one paint per size and colour.
Item {
    id: mk
    property real size: 14
    property color color: "#3672d4"
    property real gloss: 0
    width: size
    height: size

    readonly property real r: size / 2
    function half(y) { var d = y - r; return Math.sqrt(Math.max(0, r * r - d * d)) }

    // One band of the disc between two heights (fractions of the size): its chords joined by the circle's arcs.
    component Band: ShapePath {
        id: band
        property real f1: 0
        property real f2: 1
        readonly property real y1: Math.max(0.0001, f1 * mk.size)
        readonly property real y2: f2 * mk.size
        strokeColor: "transparent"
        fillGradient: LinearGradient {
            x1: 0; y1: 0; x2: 0; y2: mk.size
            GradientStop { position: 0; color: mk.gloss > 0 ? Qt.lighter(mk.color, 1 + 0.55 * mk.gloss) : mk.color }
            GradientStop { position: 0.55; color: mk.color }
            GradientStop { position: 1; color: mk.gloss > 0 ? Qt.darker(mk.color, 1 + 0.35 * mk.gloss) : mk.color }
        }
        startX: mk.r - mk.half(band.y1); startY: band.y1
        PathLine { x: mk.r + mk.half(band.y1); y: band.y1 }
        PathArc { x: mk.r + mk.half(band.y2); y: band.y2; radiusX: mk.r; radiusY: mk.r }
        PathLine { x: mk.r - mk.half(band.y2); y: band.y2 }
        PathArc { x: mk.r - mk.half(band.y1); y: band.y1; radiusX: mk.r; radiusY: mk.r }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // The cap above the horizon, then two strips with a gap between.
        Band { f1: 0; f2: 0.6 }
        Band { f1: 0.68; f2: 0.79 }
        Band { f1: 0.86; f2: 0.95 }
    }
    // The gel's highlight on the cap.
    Rectangle {
        visible: mk.gloss > 0
        x: mk.size * 0.22; y: mk.size * 0.06
        width: mk.size * 0.56; height: mk.size * 0.3
        radius: height / 2
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.75 * mk.gloss) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.08 * mk.gloss) }
        }
    }
}
