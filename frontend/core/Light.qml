pragma Singleton
import QtQuick
import Quickshell

// The light's frontend half (K59, docs/ux/texture.md "Light"). The daemon resolves the static and daytime lights
// (`light.*` tokens); the pointer lamp is a view concern (only the frontend sees the pointer, over its own surfaces),
// so it lives here: a lamp at the pointer, in output coordinates (`x`, `y`, logical px on `output`), fed by a sensor at
// each shell window's root in the pointer mode (components/LightSense.qml). `k` is the lamp's hold: 1 while the pointer
// is over a shell surface, gliding to 0 (the static light, `light.dir`) over `motion.long` when it leaves them all, or
// snapping when motion is off. Nothing here repaints by itself: a Relief reads it and repaints on each move.
//
// `originOf(win)` is the sheet's registration (the frontend's half of "the sheet is continuous in output coordinates"):
// where a layer window sits on its output, in logical px, from its anchors, margins and size. The Relief shader adds
// the fragment's own window pixel to it, so every window of an output shows the same part of the sheet.
Singleton {
    id: light

    property string output: ""
    property real x: 0
    property real y: 0
    property real k: 0

    // The glide back to the static light: a single motion.long run, gated by the glide's own running (it stops itself).
    NumberAnimation {
        id: glide
        target: light
        property: "k"
        to: 0
        duration: Theme.longMs
        easing.type: Easing.InOutQuad
    }

    // The pointer is over `out` at (px, py), output logical px. Another output's lamp is simply replaced.
    function moveTo(out, px, py) {
        glide.stop()
        output = out
        x = px
        y = py
        k = 1
    }

    // The pointer left a shell window on `out`. A leave on an output the pointer already moved on from does nothing
    // (the window it entered owns the lamp now).
    function leave(out) {
        if (out !== output || k === 0) return
        if (Theme.springOn) glide.restart()
        else k = 0
    }

    // The top-left corner of layer window `w` on its output (logical px). Layer surfaces are placed by their anchors:
    // a left or top anchor pins the margin; a right or bottom anchor pins the margin from the far edge; neither
    // centres the window on that axis (the layer-shell rule).
    function originOf(w) {
        if (!w || !w.screen || !w.anchors || !w.margins) return Qt.point(0, 0)
        var s = w.screen, a = w.anchors, m = w.margins
        var ox = a.left ? m.left : (a.right ? s.width - w.width - m.right : (s.width - w.width) / 2)
        var oy = a.top ? m.top : (a.bottom ? s.height - w.height - m.bottom : (s.height - w.height) / 2)
        return Qt.point(ox, oy)
    }
}
