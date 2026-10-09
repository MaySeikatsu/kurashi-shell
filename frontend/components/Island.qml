import QtQuick
import "../core"
import "faces"

// Island (島): the daemon decides the face (runtime.island.*); this only morphs between faces.
// One component per face id (faces/); each watches only the docs it renders and only while it is
// visible. Interruptible: width/opacity are Behaviors, so a new face retargets mid-flight.
// Animations are gated on `visible` (Ma) and armed only after the first layout so startup does
// not animate. Unknown face ids (mod faces) fall back to the clock rather than showing nothing.
// Input is presentational: the surface passes island.main's resolved bindings in `slots` and gets
// `activated(slot)` for a bound slot only. What a slot does is the daemon's call (input.dispatch).
Rectangle {
    id: isl
    property string face: "clock"
    // `{ "<slot>": {action, source, forced_by?} }`; an unbound slot is absent, never null.
    property var slots: ({})
    // left, right, middle, hover, scroll_up, scroll_down, shift_scroll_up, shift_scroll_down
    signal activated(string slot)

    function isBound(slot) { return slots[slot] !== undefined }

    property string reason: "default"   // why the daemon picked this face
    // `manual` (island.next/prev/pin via the arbiter) is a deliberate user choice, like `user`.
    readonly property bool byUser: reason === "user" || reason === "manual"

    readonly property string shown: ["clock", "media", "volume", "brightness", "notifications"].indexOf(face) >= 0 ? face : "clock"
    readonly property bool animate: armed && visible
    property bool armed: false
    Component.onCompleted: armed = true

    readonly property real faceW: shown === "media" ? media.wantW
        : shown === "volume" ? volume.wantW
        : shown === "brightness" ? bright.wantW
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
    BrightnessFace { id: bright; anchors.fill: parent; current: isl.shown === "brightness"; animate: isl.animate }
    NotificationsFace { id: notifs; anchors.fill: parent; current: isl.shown === "notifications"; animate: isl.animate }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        // A pointer only promises a click when the left click does something (unbound = no pointer).
        cursorShape: isl.isBound("left") ? Qt.PointingHandCursor : Qt.ArrowCursor
        // Hover is an event, not a poll: one dispatch per entry into the island.
        onEntered: { if (isl.isBound("hover")) isl.activated("hover") }
        onClicked: m => {
            var slot = m.button === Qt.RightButton ? "right" : m.button === Qt.MiddleButton ? "middle" : "left"
            if (isl.isBound(slot)) isl.activated(slot)
        }
        onWheel: w => {
            // Toolkits differ on which axis Shift+wheel reports, so with Shift either axis counts.
            var shift = (w.modifiers & Qt.ShiftModifier) !== 0
            var d = w.angleDelta.y !== 0 ? w.angleDelta.y : (shift ? w.angleDelta.x : 0)
            if (d === 0) return
            var slot = (shift ? "shift_scroll_" : "scroll_") + (d > 0 ? "up" : "down")
            if (isl.isBound(slot)) isl.activated(slot)
        }
    }
}
