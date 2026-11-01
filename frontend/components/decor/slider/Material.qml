import QtQuick
import "../../../core"

// Material (W53.8, docs/ux/styles.md "material"): Material 3's 2024 expressive slider (material-web tokens
// md.comp.slider, read 2026-11-01: active/inactive track height 16, outer corners full and inner corners 2 px, the handle a
// 4 × 44 bar — 2 px wide while pressed or focused — with 6 px of air on both sides, a 4 px stop indicator 4 px from the
// track's end). The value's part in `primary` (accent), the rest in `secondary-container` (the tonal `selected`), the stop
// dot in the ink on each. The host's slider is 20 px tall, so the track is 12 and the handle reaches 4 px past it top and
// bottom — the M3 handle stands taller than its track. Vertical sliders turn the same drawing. Static at rest; the
// handle's width eases on the fast curve while it is pressed.
SliderBase {
    id: sl
    property bool hovered: false
    readonly property real v: Math.max(0, Math.min(1, value))
    // The drawing in its horizontal frame (turned for a vertical slider).
    readonly property real len: vertical ? height : width
    readonly property real thick: vertical ? width : height
    readonly property real trackH: Math.max(6, Math.min(16, Math.round(thick * 0.6)))
    readonly property real handleH: Math.min(44, thick + 8)
    readonly property real handleW: pressed ? 2 : 4
    readonly property real gap: 6
    readonly property real stop: 4
    readonly property real at: Math.round((len - 4) * v)   // the handle's left edge (its 4 px slot)
    readonly property color activeC: Theme.accent
    readonly property color inactiveC: Theme.selected
    readonly property color onActive: Theme.fgOnAccent
    readonly property color onInactive: Theme.color("color.on_selected", Theme.fg)

    Item {
        id: body
        width: sl.len
        height: sl.thick
        anchors.centerIn: parent
        rotation: sl.vertical ? -90 : 0

        // The value's part: full-round at the start, 2 px at the handle.
        Item {
            readonly property real w: Math.max(0, sl.at - sl.gap)
            visible: w > 0
            y: Math.round((body.height - sl.trackH) / 2)
            width: w
            height: sl.trackH
            Rectangle { width: Math.min(parent.w, sl.trackH); height: parent.height; radius: height / 2; color: sl.activeC }
            Rectangle {
                visible: parent.w > sl.trackH / 2
                x: sl.trackH / 2
                width: parent.w - x
                height: parent.height
                radius: 2
                color: sl.activeC
            }
        }
        // The rest: 2 px at the handle, full-round at the end, with the stop indicator near its end.
        Item {
            readonly property real x0: sl.at + 4 + sl.gap
            readonly property real w: Math.max(0, body.width - x0)
            visible: w > 0
            x: x0
            y: Math.round((body.height - sl.trackH) / 2)
            width: w
            height: sl.trackH
            Rectangle { width: Math.max(0, parent.w - sl.trackH / 2); height: parent.height; radius: 2; color: sl.inactiveC }
            Rectangle {
                x: Math.max(0, parent.w - sl.trackH)
                width: Math.min(parent.w, sl.trackH)
                height: parent.height
                radius: height / 2
                color: sl.inactiveC
            }
            Rectangle {
                visible: parent.w > sl.stop + 8
                width: sl.stop
                height: sl.stop
                radius: sl.stop / 2
                x: parent.w - (sl.trackH - sl.stop) / 2 - sl.stop
                anchors.verticalCenter: parent.verticalCenter
                color: sl.onInactive
            }
        }
        // The handle: a full-round bar in primary, taller than the track.
        Rectangle {
            x: sl.at + (4 - width) / 2
            width: sl.handleW
            height: sl.handleH
            anchors.verticalCenter: parent.verticalCenter
            radius: width / 2
            color: sl.activeC
            Behavior on width {
                enabled: Theme.timed
                NumberAnimation { duration: Theme.fastMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.fastCurve }
            }
        }
    }
}
