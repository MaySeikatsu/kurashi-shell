import QtQuick
import "../../core"

// TooltipStyle (W53.0a, K80): a tooltip or balloon in this look — the dock tooltip, bar peeks. A caller keeps its own
// colours where the look leaves them (`fill(own)`, `ink(own)`: 98's pale yellow from `[decor] tooltip.fill = "info"`)
// and gives the balloon a tail toward its anchor with `tail` (XP). A look naming a tooltip part (`[slots] tooltip`,
// contract `tooltip/TooltipBase.qml`) draws the background instead: `part` is its url.
Item {
    readonly property string file: Theme.pascal(Theme.slot("tooltip"))
    readonly property bool has: file !== ""
    readonly property bool tail: Theme.decor("tooltip.tail", false) === true
    function fill(own) { var v = Theme.decor("tooltip.fill", ""); return v !== "" ? Qt.color(v) : own }
    function ink(own) { var v = Theme.decor("tooltip.on", ""); return v !== "" ? Qt.color(v) : own }
    readonly property url part: has ? Qt.resolvedUrl("tooltip/" + file + ".qml") : ""
}
