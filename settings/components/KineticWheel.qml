import QtQuick
import "../core"

// Kinetic scrolling for a page (session 17, docs/ux/settings.md "Opening, scrolling"): a wheel notch adds velocity to
// the page's own fling — notches in a row accelerate, a stop eases out on the Flickable's deceleration — and a
// touchpad's pixel deltas move the page 1:1 (its own inertia follows). Motion off: a notch moves the page at once.
// Place it inside the Flickable it drives and name it: `KineticWheel { flick: page }` (a Flickable's children live in
// its content item).
WheelHandler {
    id: kw
    property Flickable flick: null
    // Pixels per second a notch adds (one notch glides ~155 px on the pages' deceleration, a quick run ~1000 px), and how
    // close in time notches must come to build on each other.
    property real notchVelocity: 950
    property int chainMs: 240
    property real speed: 0
    property double last: 0
    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    function clampY(y) { return Math.max(0, Math.min(y, Math.max(0, flick.contentHeight - flick.height))) }
    onWheel: function (ev) {
        var f = kw.flick
        if (!f) return
        if (ev.pixelDelta.y !== 0) {
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
        kw.speed = (same ? kw.speed * 0.6 : 0) + notches * kw.notchVelocity
        kw.speed = Math.max(-f.maximumFlickVelocity, Math.min(f.maximumFlickVelocity, kw.speed))
        kw.last = now
        f.flick(0, kw.speed)
    }
}
