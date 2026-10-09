import QtQuick
import "../core"
import "faces"

// Island (島): the daemon decides the face (runtime.island.*); this only morphs between faces.
// One component per face id (faces/); each watches only the docs it renders and only while it is
// visible. Interruptible: width/opacity are Behaviors, so a new face retargets mid-flight.
// Animations are gated on `visible` (Ma) and armed only after the first layout so startup does
// not animate. Unknown face ids (mod faces) fall back to the clock rather than showing nothing.
Rectangle {
    id: isl
    property string face: "clock"
    signal primary()                 // left click
    signal secondary()               // right click
    signal scrolled(int dir)         // +1 up, -1 down

    property string reason: "default"   // why the daemon picked this face
    // `manual` (island.next/prev/pin via the arbiter) is a deliberate user choice, like `user`.
    readonly property bool byUser: reason === "user" || reason === "manual"

    readonly property string shown: ["clock", "media", "volume", "notifications"].indexOf(face) >= 0 ? face : "clock"
    readonly property bool animate: armed && visible
    property bool armed: false
    Component.onCompleted: armed = true

    readonly property real faceW: shown === "media" ? media.wantW
        : shown === "volume" ? volume.wantW
        : shown === "notifications" ? notifs.wantW : clock.wantW

    height: Theme.barH - 10
    radius: Theme.rFull
    color: Theme.containerHigh
    clip: true
    width: faceW + 2 * Theme.pad
    Behavior on width {
        enabled: isl.animate
        NumberAnimation { duration: Theme.emphMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
    }

    ClockFace { id: clock; anchors.fill: parent; current: isl.shown === "clock"; animate: isl.animate }
    MediaFace { id: media; anchors.fill: parent; current: isl.shown === "media"; animate: isl.animate }
    VolumeFace { id: volume; anchors.fill: parent; current: isl.shown === "volume"; animate: isl.animate }
    NotificationsFace { id: notifs; anchors.fill: parent; current: isl.shown === "notifications"; animate: isl.animate }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => { if (m.button === Qt.RightButton) isl.secondary(); else isl.primary() }
        onWheel: w => { if (w.angleDelta.y !== 0) isl.scrolled(w.angleDelta.y > 0 ? 1 : -1) }
    }
}
