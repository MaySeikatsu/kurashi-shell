import QtQuick
import "../../core"
import "../faces"

// The island's compact face inside the Stage's shape (W21): the same face component the bar's pill draws, so while the
// shape is out the face stays where the pill was (the card's header, inside the bar) and the morph shows one island.
// A face is made only while `active` (the shape is out); a mod's face, or none, draws nothing here.
Loader {
    id: cf
    property string face: "clock"
    property bool animate: false
    readonly property real wantW: item ? item.wantW : 0
    active: false
    sourceComponent: {
        switch (face) {
        case "clock": return clockC
        case "media": return mediaC
        case "volume": return volumeC
        case "brightness": return brightC
        case "notifications": return notifC
        case "power": return powerC
        case "bluetooth": return btC
        default: return null
        }
    }
    readonly property var detail: (Store.docs["runtime.island.main"] || ({})).detail || ({})
    Component { id: clockC; ClockFace { current: true; animate: cf.animate } }
    Component { id: mediaC; MediaFace { current: true; animate: cf.animate } }
    Component { id: volumeC; VolumeFace { current: true; animate: cf.animate } }
    Component { id: brightC; BrightnessFace { current: true; animate: cf.animate } }
    Component { id: notifC; NotificationsFace { current: true; animate: cf.animate } }
    Component { id: powerC; PowerFace { current: true; animate: cf.animate; line: cf.detail.power ?? "" } }
    Component { id: btC; BluetoothFace { current: true; animate: cf.animate; line: cf.detail.bluetooth ?? "" } }
}
