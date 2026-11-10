import QtQuick

// The notebook's top sheet (W69; docs/ux/webdock.md "Page styles" › Notebook), drawn in its own box (`geom.sheet`; the
// caller places this item there and puts the header and the page on it): the page's ground (`surface_container`) with
// faint rules every `ruleGap` px, the heading rule under the header (`headY`) in the accent, the punched slots along
// the bound edge (the cover shows through them) and a thin gutter shadow along that edge. Static (Ma); the page turn
// captures this item with what lies on it.
Item {
    id: sh

    property var theme: null
    property NotebookGeom geom: null
    // The heading rule's place (sheet px from the top), or < 0 for none.
    property real headY: -1
    property real ruleGap: 24

    readonly property string edge: geom ? geom.edge : "right"
    readonly property color paper: theme ? theme.container : "#252329"
    readonly property color hair: theme ? Qt.alpha(theme.outline, 0.55) : "#555"
    readonly property color rule: theme ? Qt.alpha(theme.outline, 0.32) : "#444"
    readonly property color coverC: theme ? Qt.tint(theme.containerHigh, Qt.alpha(theme.accent, 0.3)) : "#6b5235"
    // A point of the binding's frame in this sheet's px: `a` along the bound edge from the sheet's start, `d` in from it.
    function pt(a, d) {
        if (edge === "right") return Qt.point(width - d, a)
        if (edge === "left") return Qt.point(d, a)
        if (edge === "bottom") return Qt.point(a, height - d)
        return Qt.point(a, d)
    }
    readonly property bool sideways: edge === "left" || edge === "right"

    Rectangle {
        anchors.fill: parent
        color: sh.paper
        border.width: sh.theme && sh.theme.outlineW > 0 ? sh.theme.outlineW : 1
        border.color: sh.theme && sh.theme.outlineW > 0 ? sh.theme.outlineColor : sh.hair
        topLeftRadius: sh.edge === "left" || sh.edge === "top" ? 0 : 3
        topRightRadius: sh.edge === "right" || sh.edge === "top" ? 0 : 3
        bottomLeftRadius: sh.edge === "left" || sh.edge === "bottom" ? 0 : 3
        bottomRightRadius: sh.edge === "right" || sh.edge === "bottom" ? 0 : 3
        antialiasing: true
    }
    // The rules (text lines run across the sheet whichever edge it is bound on).
    Repeater {
        model: Math.max(0, Math.floor((sh.height - 16) / sh.ruleGap))
        delegate: Rectangle {
            required property int index
            x: 1
            y: 16 + index * sh.ruleGap
            width: sh.width - 2
            height: 1
            color: sh.rule
        }
    }
    Rectangle {
        visible: sh.headY >= 0
        x: 1
        y: Math.round(sh.headY)
        width: sh.width - 2
        height: 1
        color: sh.theme ? Qt.alpha(sh.theme.accent, 0.7) : "#c9404b"
    }
    // The gutter: a shade along the bound edge, fading over 16 px.
    Rectangle {
        readonly property real t: 16
        x: sh.edge === "right" ? sh.width - t : 0
        y: sh.edge === "bottom" ? sh.height - t : 0
        width: sh.sideways ? t : sh.width
        height: sh.sideways ? sh.height : t
        gradient: Gradient {
            orientation: sh.sideways ? Gradient.Horizontal : Gradient.Vertical
            GradientStop {
                position: 0
                color: sh.edge === "right" || sh.edge === "bottom" ? "transparent" : (sh.theme ? Qt.alpha(sh.theme.line, 0.22) : "#3000")
            }
            GradientStop {
                position: 1
                color: sh.edge === "right" || sh.edge === "bottom" ? (sh.theme ? Qt.alpha(sh.theme.line, 0.22) : "#3000") : "transparent"
            }
        }
    }
    // The punched slots: the cover shows through each (a shade darker: it lies in the sheet's shadow).
    Repeater {
        model: sh.geom ? sh.geom.loops : []
        delegate: Rectangle {
            required property var modelData
            readonly property real along: 4
            readonly property real across: 6.5
            readonly property point c: sh.pt(modelData - sh.geom.lip, sh.geom.holeD - sh.geom.sheetD)
            width: sh.sideways ? across : along
            height: sh.sideways ? along : across
            x: c.x - width / 2
            y: c.y - height / 2
            radius: 1.5
            color: Qt.darker(sh.coverC, 1.3)
            antialiasing: true
        }
    }
}
