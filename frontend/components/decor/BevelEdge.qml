import QtQuick
import "../../core"

// The bevel (W53.0a, K80; docs/ux/styles.md "Chrome bevel"): two pairs of lines over a face's edge — outer
// `Theme.bevelLight`/`bevelDark`, inner `bevelLight2`/`bevelDark2` — light falling from the top left, as Windows 98
// draws a raised button (98.css: the dark lines lie over the light ones at the top-right and bottom-left corners).
// `sunk` swaps the pairs: a pressed button, a sunken well. Lines are whole device pixels (`Theme.crisp`), so 1 px stays
// crisp at 1.25 and 1.5. Static: it paints once per size and colour. Block draws it under a bevel chrome; a decor part
// (a caption's close button, a scroll thumb, the tray well) uses it on its own, with `w` and the colours it wants.
Item {
    id: bv
    property bool sunk: false
    property real w: Theme.crisp(Theme.bevelW, Screen.devicePixelRatio)
    property color light: Theme.bevelLight
    property color light2: Theme.bevelLight2
    property color dark2: Theme.bevelDark2
    property color dark: Theme.bevelDark
    // Top-left and bottom-right colours of the outer and inner pairs.
    readonly property color tl: sunk ? dark : light
    readonly property color br: sunk ? light : dark
    readonly property color tl2: sunk ? dark2 : light2
    readonly property color br2: sunk ? light2 : dark2

    component Pair: Item {
        id: pr
        property color a
        property color b
        Rectangle { x: 0; y: 0; width: pr.width; height: bv.w; color: pr.a }
        Rectangle { x: 0; y: 0; width: bv.w; height: pr.height; color: pr.a }
        Rectangle { x: 0; y: pr.height - bv.w; width: pr.width; height: bv.w; color: pr.b }
        Rectangle { x: pr.width - bv.w; y: 0; width: bv.w; height: pr.height; color: pr.b }
    }

    Pair { anchors.fill: parent; a: bv.tl; b: bv.br }
    Pair { anchors.fill: parent; anchors.margins: bv.w; a: bv.tl2; b: bv.br2 }
}
