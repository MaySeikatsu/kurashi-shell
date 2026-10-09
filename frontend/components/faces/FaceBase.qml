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
    // Natural content width; the Island sizes itself from the current face.
    property real wantW: 0

    property bool created: false
    Component.onCompleted: created = true
    opacity: current && created ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
        enabled: face.animate
        NumberAnimation { duration: Theme.emphMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
    }
}
