import QtQuick
import "../../../core"

// Slip (W53.7, docs/ux/styles.md §9 washi): a tooltip — and a toast, which the shell draws as the look's tooltip — as a
// slip of washi (短冊 tanzaku, 付箋): the paper a shade lighter than the sheet under it, a sumi hairline round it with the
// corners barely softened (2 px, as torn-and-trimmed paper), and a thin beni rule down its start edge, the slip's one
// colour. No tail, no shadow (paper lies flat; the card under it keeps its own elevation). Roles only (rule 4); static.
TooltipBase {
    id: tt
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property string fill: Theme.decor("tooltip.fill", "")
    readonly property int r: Math.max(0, Theme.decor("tooltip.radius", 2))
    // Session 29 (the user: "make sure … notification toast follows too", and asked about the corners: "radius"): the
    // slip's line is the frame's line where the frame draws one (its colour flow too); a toast (`sheet`) takes the
    // sheets' radius and corner shape, as every sheet does (I489). A small tip stays the slip: 2 px corners.
    readonly property color paper: tt.fill !== "" ? tt.fill : Theme.color("color.surface_container_lowest", "#fbf8f1")
    readonly property color lineInk: Theme.frameOutline ? Theme.surfaceLineColor : Qt.alpha(Theme.fg, 0.55)
    readonly property string join: tt.sheet && Theme.joinCorner !== "round" && Theme.joinCorner !== "" ? Theme.joinCorner : ""
    // (the shaped corner: the sheets' radius, a third of the slip's height at most; the rule keeps clear of it)
    readonly property real shapedR: Math.min(Theme.rLg, tt.height / 3)
    readonly property real ruleInset: !tt.sheet ? 5 : (tt.join !== "" ? tt.shapedR + 2 : tt.shapedR * 0.6 + 2)
    Rectangle {
        visible: tt.join === ""
        anchors.fill: parent
        radius: tt.sheet ? tt.shapedR : tt.r
        color: tt.paper
        border.width: tt.hair
        border.color: tt.lineInk
    }
    // (by file: this part is linked into hosts whose components folder may differ; made only under a corner shape)
    Loader {
        anchors.fill: parent
        active: tt.join !== ""
        source: active ? "../../SquircleRect.qml" : ""
        onLoaded: {
            item.radius = Qt.binding(function () { return tt.shapedR })
            item.join = Qt.binding(function () { return tt.join })
            item.color = Qt.binding(function () { return tt.paper })
            item.borderWidth = Qt.binding(function () { return tt.hair })
            item.borderColor = Qt.binding(function () { return tt.lineInk })
        }
    }
    Rectangle {
        x: 4
        anchors { top: parent.top; bottom: parent.bottom; topMargin: tt.ruleInset; bottomMargin: tt.ruleInset }
        width: Math.max(2, 2 * tt.hair)
        color: Theme.accent
        opacity: 0.85
    }
}
