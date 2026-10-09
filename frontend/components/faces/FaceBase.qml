import QtQuick
import "../../core"

// Base of every island face. The Island sets `current`; the face crossfades itself and reports
// `live` (visible, including while fading out) so subclasses subscribe to their docs only while
// they can be seen (Ma: an invisible face holds no subscription, which stops its service).
Item {
    id: face
    property bool current: false
    property bool animate: false
    readonly property bool live: visible
    // Natural content width; the Island sizes itself from the current face.
    property real wantW: 0

    opacity: current ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
        enabled: face.animate
        NumberAnimation { duration: Theme.emphMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
    }
}
