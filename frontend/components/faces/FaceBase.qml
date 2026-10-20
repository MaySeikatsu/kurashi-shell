import QtQuick
import "../../core"

// Base of every island face. The Island sets `current`; the face crossfades itself and reports
// `live` (visible, including while fading out) so subclasses subscribe to their docs only while
// they can be seen (Ma: an invisible face holds no subscription, which stops its service).
// The Island creates a face when it becomes current and drops it once faded out (B7), so a new
// face starts transparent and fades in from its first frame.
Item {
    id: face
    property bool current: false
    property bool animate: false
    readonly property bool live: visible
    // Natural content width (a row, on a top or bottom bar); the Island sizes itself from the current face.
    property real wantW: 0
    // A side bar's pill is as wide as the bar is thick, so there the face is a column (its glyph over a short
    // value) and `wantH` is its natural height. The Island sets `vertical`.
    property bool vertical: false
    property real wantH: 0

    property bool created: false
    Component.onCompleted: created = true
    opacity: current && created ? 1 : 0
    visible: opacity > 0
    // A face change (W21, Capsule's FadeScale): the new face rises into place from a little below and a little smaller;
    // the old one is swallowed (it shrinks and lifts away) instead of only fading. Both ride the opacity animation.
    scale: current ? 0.92 + 0.08 * opacity : 0.7 + 0.3 * opacity
    transform: Translate { y: (face.current ? 1 : -1) * (1 - face.opacity) * 6 }
    Behavior on opacity {
        enabled: face.animate
        NumberAnimation { duration: Theme.emphMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
    }
}
