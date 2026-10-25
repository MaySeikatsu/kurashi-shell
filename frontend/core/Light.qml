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
// The spotlight (K61) uses the same lamp as its aim: the beam lands on the pointer while it is over a shell surface of
// that output and glides back to the output's middle with `k` (Relief: aim = middle + (pointer − middle) × k).
//
// `pictures` (I167): the pictures the light never falls on — album covers, avatars, notification images, wallpaper
// thumbnails, web pages. A picture registers itself with its window (`addPicture(item, Window.window)`); every Relief in
// that window cuts it out (up to four), even when it lies over the content (`texture.text`, `texture.controls`).
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
    // [{item, win}] (I167): see the header.
    property var pictures: []

    function addPicture(item, win) {
        if (!item || !win) return
        var l = pictures.filter(function (e) { return e.item !== item })
        l.push({ item: item, win: win })
        pictures = l
    }
    function removePicture(item) {
        var l = pictures.filter(function (e) { return e.item !== item })
        if (l.length !== pictures.length) pictures = l
    }

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

    // The exclusive zones other layer windows hold on each output (the bars): `{ "<output>": [{win, edge, size}] }`.
    // A window that respects exclusive zones (not ExclusionMode.Ignore) is placed by the compositor inside what they
    // leave; its origin must count them, or its sheet sits a bar's thickness off everyone else's (W34 sidebar report).
    property var zones: ({})
    function setZone(win, output, edge, size) {
        var n = Object.assign({}, zones)
        for (var k in n) n[k] = n[k].filter(function (z) { return z.win !== win })
        if (output !== "" && size > 0) n[output] = (n[output] || []).concat([{ win: win, edge: edge, size: size }])
        zones = n
    }
    function zoneOf(w, edge) {
        if (!w || !w.screen || w.exclusionMode === ExclusionMode.Ignore) return 0
        var list = zones[w.screen.name] || []
        var sum = 0
        for (var i = 0; i < list.length; i++)
            if (list[i].win !== w && list[i].edge === edge) sum += list[i].size
        return sum
    }
    // The top-left corner of layer window `w` on its output (logical px). Layer surfaces are placed by their anchors:
    // a left or top anchor pins the margin; a right or bottom anchor pins the margin from the far edge; neither
    // centres the window on that axis (the layer-shell rule).
    // Inside the exclusive zones it respects.
    function originOf(w) {
        if (!w || !w.screen || !w.anchors || !w.margins) return Qt.point(0, 0)
        var s = w.screen, a = w.anchors, m = w.margins
        var zl = zoneOf(w, "left"), zr = zoneOf(w, "right"), zt = zoneOf(w, "top"), zb = zoneOf(w, "bottom")
        var ox = a.left ? zl + m.left : (a.right ? s.width - zr - w.width - m.right : zl + (s.width - zl - zr - w.width) / 2)
        var oy = a.top ? zt + m.top : (a.bottom ? s.height - zb - w.height - m.bottom : zt + (s.height - zt - zb - w.height) / 2)
        return Qt.point(ox, oy)
    }
}
