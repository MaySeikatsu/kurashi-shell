import QtQuick
import "../core"

// FrameHost (W25, K50): the active decor pack's frame — its corners, ornaments and bevels — drawn over a block's edge
// (or, as kind "ground", over a whole surface's ground: the lock). The frame is `Theme.frame`, a name the pack carries
// as data (`[slots] frame`, token `decor.frame`); it loads `frames/<Name>.qml` (kebab-case → PascalCase) and never
// compares the name (rule 4). Nothing is made while the pack has none. A frame is static: it paints once per size and
// colour; any motion in one runs only while `animate` (visible) and `Theme.springOn` (Ma).
// Kinds: "card" (a panel, a desk card, the island card: the full frame), "small" (bar groups, keys, tiles, buttons: a
// restrained edge, or nothing) and "ground" (a surface's backdrop). Frames share the contract of `frames/FrameBase.qml`.
Loader {
    id: fh
    property real radius: 0
    property bool pressed: false
    property bool animate: visible
    // K62: whom a frame that draws a pen line salts it with (the block), and an explicit salt (≥ 0) instead.
    property Item anchor: null
    property int penSeed: -1
    property string kind: height >= 64 && width >= 120 ? "card" : "small"
    // The frame draws a ground of its own (kind "ground"): the surface hides its chrome-derived ground meanwhile.
    readonly property bool grounds: item !== null && item.grounds === true
    // The frame draws the block's outline itself (FrameBase.drawsOutline): the block then leaves its straight line out.
    readonly property bool drawsOutline: item !== null && item.drawsOutline === true
    readonly property string file: {
        var n = Theme.frame
        if (!n) return ""
        return n.split("-").map(function (w) { return w.charAt(0).toUpperCase() + w.slice(1) }).join("")
    }
    active: file !== "" && width > 0 && height > 0
    source: active ? Qt.resolvedUrl("frames/" + file + ".qml") : ""
    onLoaded: {
        item.radius = Qt.binding(function () { return fh.radius })
        item.kind = Qt.binding(function () { return fh.kind })
        item.pressed = Qt.binding(function () { return fh.pressed })
        item.animate = Qt.binding(function () { return fh.animate && Theme.springOn })
        item.anchor = Qt.binding(function () { return fh.anchor })
        item.penSeed = Qt.binding(function () { return fh.penSeed })
    }
}
