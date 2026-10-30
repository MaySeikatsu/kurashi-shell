import QtQuick
import "../../core"

// MenuStyle (W53.0a, K80): how a menu row looks in this look — the tray menu, the dock menu, launcher rows. A caller
// keeps its own metrics where the look leaves them (`rowH(own)`, `radius(own)`), reads the highlight's shape
// (`highlight`: capsule = today's, bar = a full-width band as 9x/XP, inset = a band inside the menu's margin) and the
// separator (`separator`: line = today's, etched = a dark and a light line, space = a gap). A look naming a menu part
// (`[slots] menu`, contract `menu/MenuRowBase.qml`) draws each row's background instead: `rowBackground` loads it.
QtObject {
    readonly property string part: Theme.pascal(Theme.slot("menu"))
    readonly property bool has: part !== ""
    readonly property string highlight: Theme.decor("menu.highlight", "capsule")
    readonly property string separator: Theme.decor("menu.separator", "line")
    function rowH(own) { var v = Theme.decor("menu.row", 0); return v > 0 ? v : own }
    function radius(own) { var v = Theme.decor("menu.radius", -1); return v >= 0 ? v : own }
    // The look's row background (null without a menu part): a Loader's `source` for each row.
    readonly property url rowBackground: has ? Qt.resolvedUrl("menu/" + part + ".qml") : ""
}
