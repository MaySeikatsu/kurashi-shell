import QtQuick
import "../core"

// Island (島): the daemon decides the face (runtime.island.*); this only morphs between faces.
// Interruptible: width/opacity are Behaviors, so a new face retargets mid-flight. Animations are
// gated on `visible` (Ma) and armed only after the first layout so startup does not animate.
Rectangle {
    id: isl
    property string face: "clock"
    property string clockText: ""
    property string mediaText: ""
    signal primary()                 // left click
    signal secondary()               // right click
    signal scrolled(int dir)         // +1 up, -1 down

    property string reason: "default"   // why the daemon picked this face
    // `manual` (island.next/prev/pin via the arbiter) is a deliberate user choice, like `user`.
    readonly property bool byUser: reason === "user" || reason === "manual"

    readonly property bool media: face === "media"
    readonly property bool animate: armed && visible
    property bool armed: false
    Component.onCompleted: armed = true

    height: Theme.barH - 10
    radius: Theme.rFull
    color: Theme.containerHigh
    clip: true
    width: (media ? mediaLabel.implicitWidth : clockLabel.implicitWidth) + 2 * Theme.pad
    Behavior on width {
        enabled: isl.animate
        NumberAnimation { duration: Theme.emphMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
    }

    Text {
        id: clockLabel
        anchors.centerIn: parent
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: isl.clockText
        opacity: isl.media ? 0 : 1
        visible: opacity > 0
        Behavior on opacity {
            enabled: isl.animate
            NumberAnimation { duration: Theme.emphMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
        }
    }
    Text {
        id: mediaLabel
        anchors.centerIn: parent
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: isl.mediaText
        opacity: isl.media ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            enabled: isl.animate
            NumberAnimation { duration: Theme.emphMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
        }
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => { if (m.button === Qt.RightButton) isl.secondary(); else isl.primary() }
        onWheel: w => { if (w.angleDelta.y !== 0) isl.scrolled(w.angleDelta.y > 0 ? 1 : -1) }
    }
}
