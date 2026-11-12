import QtQuick
import "../core"

// Kinetic scrolling for anything that scrolls (session 17, docs/ux/settings.md "Opening, scrolling"; shared since B42, I396):
// a wheel notch adds velocity to the view's own fling — notches in a row accelerate, a stop eases out on the deceleration
// below — and a touchpad's pixel deltas move the view 1:1. Motion off: a notch moves the view at once.
// Place it inside the Flickable, ListView or GridView it drives and name it: `KineticWheel { view: list }`.
// It drives a view with `interactive: false` too (the launcher's lists, which only the keyboard moved before).
WheelHandler {
    id: kw
    property Flickable view: null
    // A row that scrolls sideways (the sidebar's tabs, session 30): the wheel's notches move it along x (a touchpad's
    // sideways swipe too).
    property bool horizontal: false
    // Pixels per second a notch adds (one notch glides ~155 px on this deceleration, a quick run ~1000 px), and how close in
    // time notches must come to build on each other.
    property real notchVelocity: 950
    property int chainMs: 240
    property real speed: 0
    property double last: 0
    target: null
    // A view with nothing to scroll leaves the wheel to what lies under it.
    enabled: !!view && (horizontal ? view.contentWidth > view.width + 1 : view.contentHeight > view.height + 1)
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    Component.onCompleted: {
        if (!view) return
        view.flickDeceleration = 2900
        view.maximumFlickVelocity = 7000
        view.boundsBehavior = Flickable.StopAtBounds
    }
    function clampX(x) {
        var start = view.originX - view.leftMargin
        var end = view.originX + view.contentWidth + view.rightMargin - view.width
        return Math.max(start, Math.min(x, Math.max(start, end)))
    }
    function clampY(y) {
        var top = view.originY - view.topMargin
        var end = view.originY + view.contentHeight + view.bottomMargin - view.height
        return Math.max(top, Math.min(y, Math.max(top, end)))
    }
    onWheel: function (ev) {
        var f = kw.view
        if (!f) return
        // A touchpad scrolls in phases. A wheel has none, and since Qt 6.12 it reports a pixelDelta too (B42), so that delta
        // alone cannot tell them apart.
        if (kw.horizontal) {
            // (a wheel's notch, or a touchpad's swipe either way, moves the row along x)
            var px = ev.pixelDelta.x !== 0 ? ev.pixelDelta.x : ev.pixelDelta.y
            if (ev.phase !== Qt.NoScrollPhase) { f.cancelFlick(); f.contentX = kw.clampX(f.contentX - px); return }
            var n = (ev.angleDelta.x !== 0 ? ev.angleDelta.x : ev.angleDelta.y) / 120
            if (n === 0) return
            f.contentX = kw.clampX(f.contentX - n * 60)
            return
        }
        if (ev.phase !== Qt.NoScrollPhase) {
            if (ev.pixelDelta.y === 0) return
            f.cancelFlick()
            f.contentY = kw.clampY(f.contentY - ev.pixelDelta.y)
            kw.speed = 0
            return
        }
        var notches = ev.angleDelta.y / 120
        if (notches === 0) return
        if (!Theme.springOn) {
            f.contentY = kw.clampY(f.contentY - notches * 96)
            return
        }
        var now = Date.now()
        var same = now - kw.last < kw.chainMs && (kw.speed > 0) === (notches > 0)
        // The decay follows the notch's size, so a high-resolution wheel's eight 1/8 events build what one full notch does.
        kw.speed = (same ? kw.speed * Math.pow(0.6, Math.abs(notches)) : 0) + notches * kw.notchVelocity
        kw.speed = Math.max(-f.maximumFlickVelocity, Math.min(f.maximumFlickVelocity, kw.speed))
        kw.last = now
        f.flick(0, kw.speed)
    }
}
