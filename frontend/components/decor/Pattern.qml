import QtQuick
import "../../core"

// Pattern (W53.4, K80): the look's ground pattern (`[decor] pattern.kind`) over a fill and under its content — Aqua's
// pinstripes (`stripes`: a 1 × `pattern.period` px tile, the lower half dark), brushed metal (`brushed`: a 256 × 64
// tile of fine streaks), or (W53.6) a ruled `grid`, pixel `dots` or a `checker` of `pattern.period` px cells, tiled from `decor/textures/` (tools/styles/patterns.py, CC0) at `pattern.strength` opacity. The
// tile carries no colour: it darkens whatever fill lies beneath, so every palette fits (rule 4). One Image, no Canvas,
// nothing per frame (Ma). `kind` lets a part ask for one look-independent ("" = the look's). With a rounded `radius` the
// tile keeps 0.3 × radius off every edge, so its square corner stays inside the curve (no mask, no layer).
Item {
    id: pt
    property string kind: ""
    property real strength: -1
    property real radius: 0
    readonly property string k: kind !== "" ? kind : Theme.decor("pattern.kind", "none")
    readonly property real s: strength >= 0 ? strength : Theme.decor("pattern.strength", 0)
    readonly property int period: Math.max(2, Math.min(8, Theme.decor("pattern.period", 4)))
    readonly property bool on: k !== "none" && s > 0
    visible: on
    Image {
        anchors.fill: parent
        anchors.margins: Math.ceil(0.3 * pt.radius)
        visible: pt.on
        // Every periodic kind is `textures/<kind>-<period>.png` (W53.6 adds grid, dots, checker): no list here.
        source: !pt.on ? "" : pt.k === "brushed" ? Qt.resolvedUrl("textures/brushed.png")
            : Qt.resolvedUrl("textures/" + pt.k + "-" + pt.period + ".png")
        fillMode: Image.Tile
        smooth: false
        opacity: pt.s
    }
}
