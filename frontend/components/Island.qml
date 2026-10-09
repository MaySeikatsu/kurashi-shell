import QtQuick
import "../core"
import "../core/mods.js" as Mods
import "faces"

// Island (島): the daemon decides the face (runtime.island.*); this only morphs between faces.
// One component per core face id (faces/); each watches only the docs it renders and only while it is
// visible. Interruptible: width/opacity are Behaviors, so a new face retargets mid-flight.
// Animations are gated on `visible` (Ma) and armed only after the first layout so startup does
// not animate. A mod's face (K28) draws its Face.qml, loaded only while it is the face; a face the
// `mods` document names no file for (mod off, or not yet loaded) falls back to the clock, not to nothing.
// Input is presentational: the surface passes island.main's resolved bindings in `slots` and gets
// `activated(slot)` for a bound slot only. What a slot does is the daemon's call (input.dispatch).
Item {
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

    readonly property var modsDoc: Store.docs["mods"]
    readonly property bool coreFace: ["clock", "media", "volume", "brightness", "notifications"].indexOf(face) >= 0
    readonly property bool isModFace: !coreFace && face !== "" && Mods.qmlOf(modsDoc, "island-face:" + face) !== ""
    readonly property string shown: (coreFace || isModFace) ? face : "clock"
    readonly property bool animate: armed && visible
    property bool armed: false
    Component.onCompleted: armed = true

    readonly property real faceW: {
        var l = [clock, media, volume, bright, notifs]
        for (var i = 0; i < l.length; i++)
            if (l[i].current && l[i].item) return l[i].item.wantW
        if (modFace.item) return modFace.item.wantW ?? modFace.item.implicitWidth
        return 0
    }

    height: Theme.barH - 10
    width: faceW + 2 * Theme.pad
    Behavior on width {
        enabled: isl.animate
        NumberAnimation { duration: Theme.emphMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
    }

    // The pill is what is drawn: the faces paint inside it and nothing outside it.
    Rectangle {
        id: pill
        anchors.fill: parent
        radius: Theme.rFull
        color: Theme.containerHigh
        clip: true

        // A face exists only while it is current or still fading out: the four idle faces cost
        // ~1 MiB per bar, i.e. per output (B7, docs/BENCH.md).
        FaceSlot { id: clock; face: "clock"; sourceComponent: ClockFace { current: clock.current; animate: isl.animate } }
        FaceSlot { id: media; face: "media"; sourceComponent: MediaFace { current: media.current; animate: isl.animate } }
        FaceSlot { id: volume; face: "volume"; sourceComponent: VolumeFace { current: volume.current; animate: isl.animate } }
        FaceSlot { id: bright; face: "brightness"; sourceComponent: BrightnessFace { current: bright.current; animate: isl.animate } }
        FaceSlot { id: notifs; face: "notifications"; sourceComponent: NotificationsFace { current: notifs.current; animate: isl.animate } }

        // A mod's compact face (K28): its Face.qml, instantiated only while it is the face. It is not faded:
        // the next face replaces it at once, and the pill's width still animates.
        ModLoader {
            id: modFace
            provide: "island-face:" + isl.face
            shown: isl.isModFace
            anchors.centerIn: parent
        }
    }

    // Keeps its face while current and, after that, until the face has faded out.
    component FaceSlot: Loader {
        id: slot
        required property string face
        readonly property bool current: isl.shown === face
        property bool fading: false
        onCurrentChanged: fading = !current && item !== null && item.visible
        anchors.fill: parent
        active: current || fading
        Connections {
            target: slot.item
            function onVisibleChanged() { if (!slot.item.visible) slot.fading = false }
        }
    }

    // The pointer target is the bar's full thickness (review #11: at least 32 px), centred on the pill.
    // It is a sibling of the pill, not a child: a clipping parent does not deliver pointer events to
    // children outside it, and the pill keeps its clip.
    MouseArea {
        anchors.centerIn: parent
        width: parent.width
        height: Theme.barH
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
