import QtQuick
import QtQuick.Effects

// The notebook's back layer (W69; docs/ux/webdock.md "Page styles" › Notebook): the cover board — a surface container
// tone with the accent in it (the `book` form's cover recipe), outlined as the look outlines a card — and the two sheets
// under the top one, whose edges show on the free side. Its shadow is the look's (soft or hard), as the phone's. Static:
// it changes only with the card's size or the theme (Ma). The top sheet and the coil are NotebookSheet and NotebookWire.
Item {
    id: nb

    property var theme: null
    property NotebookGeom geom: null
    property Component box: null

    readonly property bool keycap: theme ? theme.ringW > 0 : false
    readonly property real castX: keycap ? Math.round(theme.sinkX * 1.5) : 0
    readonly property real castY: keycap ? Math.round(theme.sinkY * 1.5) : 0
    readonly property color coverC: theme ? Qt.tint(Qt.tint(theme.containerHigh, Qt.alpha(theme.outline, 0.22)), Qt.alpha(theme.accent, 0.24)) : "#6b5235"
    // The cover's edge: the look's outline, or (a look without one) a line a shade darker than the board.
    readonly property real edgeW: theme && theme.outlineW > 0 ? theme.outlineW : 1
    readonly property color edgeC: theme && theme.outlineW > 0 ? theme.outlineColor : Qt.darker(coverC, 1.35)
    readonly property real coverR: theme ? Math.round(Math.max(2, Math.min(10, theme.rLg * 0.5))) : 8
    readonly property color paper: theme ? theme.container : "#252329"
    readonly property color hair: theme ? Qt.alpha(theme.outline, 0.55) : "#555"

    // (soft chrome: the drop shadow under the cover; made only while the theme has one)
    Loader {
        x: nb.geom ? nb.geom.cover.x : 0
        y: nb.geom ? nb.geom.cover.y : 0
        width: nb.geom ? nb.geom.cover.width : 0
        height: nb.geom ? nb.geom.cover.height : 0
        active: nb.theme !== null && nb.theme.softR > 0
        sourceComponent: RectangularShadow {
            offset.x: nb.theme.shadowX
            offset.y: nb.theme.shadowY
            blur: nb.theme.softR
            spread: -1
            radius: nb.coverR
            color: nb.theme.softColor
        }
    }
    FrameBox {
        box: nb.box
        visible: nb.castX !== 0 || nb.castY !== 0
        x: (nb.geom ? nb.geom.cover.x : 0) + nb.castX
        y: (nb.geom ? nb.geom.cover.y : 0) + nb.castY
        width: nb.geom ? nb.geom.cover.width : 0
        height: nb.geom ? nb.geom.cover.height : 0
        radius: nb.coverR
        color: nb.theme ? nb.theme.line : "black"
    }
    FrameBox {
        box: nb.box
        x: nb.geom ? nb.geom.cover.x : 0
        y: nb.geom ? nb.geom.cover.y : 0
        width: nb.geom ? nb.geom.cover.width : 0
        height: nb.geom ? nb.geom.cover.height : 0
        radius: nb.coverR
        color: nb.coverC
        borderWidth: nb.edgeW
        borderColor: nb.edgeC
    }
    // The sheets under the top one, the lower one first.
    Repeater {
        model: 2
        delegate: Rectangle {
            required property int index
            readonly property rect r: nb.geom ? (index === 0 ? nb.geom.under2 : nb.geom.under1) : Qt.rect(0, 0, 0, 0)
            x: r.x
            y: r.y
            width: r.width
            height: r.height
            color: Qt.darker(nb.paper, index === 0 ? 1.14 : 1.07)
            border.width: 1
            border.color: nb.hair
            topLeftRadius: nb.geom && (nb.geom.bindLeft || nb.geom.bindTop) ? 0 : 3
            topRightRadius: nb.geom && (nb.geom.bindRight || nb.geom.bindTop) ? 0 : 3
            bottomLeftRadius: nb.geom && (nb.geom.bindLeft || nb.geom.bindBottom) ? 0 : 3
            bottomRightRadius: nb.geom && (nb.geom.bindRight || nb.geom.bindBottom) ? 0 : 3
            antialiasing: true
        }
    }
}
