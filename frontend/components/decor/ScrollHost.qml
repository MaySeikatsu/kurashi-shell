import QtQuick
import "../../core"

// ScrollHost (W53.7/W53.8, K80; DESIGN-SYSTEM §4 "Decor slots"): the look's scroll bar on a list — the host the `scroll`
// slot lacked (the shell's lists are Flickables without a ScrollBar). A caller puts one over its Flickable's edge and
// names it in `flick`; while the look names a scroll part (`[slots] scroll`, contract `scroll/ScrollBase.qml`) and the
// content overflows, the part is made, at `ScrollStyle.width(10)` px, told the view's `size` and `position`, and its
// arrows step the view by `stepPx`. A press on the bar pages toward the pointer and a drag moves the thumb with it. No
// part, or nothing to scroll: nothing is made and the host is 0 px wide (a look without one stays pixel-identical).
// Static: it changes only when the view moves.
Item {
    id: sh
    property Flickable flick: null
    property int orientation: Qt.Vertical
    // One arrow's step (px): a row.
    property real stepPx: 40
    ScrollStyle { id: ss }
    readonly property bool vert: orientation === Qt.Vertical
    readonly property real view: !flick ? 0 : (vert ? flick.height : flick.width)
    readonly property real content: !flick ? 0 : (vert ? flick.contentHeight : flick.contentWidth)
    readonly property bool overflows: content > view + 1
    readonly property bool shown: ss.has && flick !== null && overflows
    readonly property real thickness: shown ? ss.width(10) : 0
    width: vert ? thickness : (flick ? flick.width : 0)
    height: vert ? (flick ? flick.height : 0) : thickness
    visible: shown

    function scrollTo(px) {
        if (!flick) return
        var max = Math.max(0, content - view)
        var v = Math.max(0, Math.min(max, px))
        if (vert) flick.contentY = v + flick.originY
        else flick.contentX = v + flick.originX
    }
    function at() { return !flick ? 0 : (vert ? flick.contentY - flick.originY : flick.contentX - flick.originX) }

    Loader {
        id: part
        anchors.fill: parent
        active: sh.shown
        source: active ? ss.part : ""
        onLoaded: {
            item.orientation = Qt.binding(function () { return sh.orientation })
            item.size = Qt.binding(function () { return sh.content > 0 ? Math.min(1, sh.view / sh.content) : 1 })
            item.position = Qt.binding(function () { return sh.content > 0 ? Math.max(0, sh.at() / sh.content) : 0 })
            item.pressed = Qt.binding(function () { return drag.pressed })
            item.hovered = Qt.binding(function () { return drag.containsMouse })
            item.step.connect(function (d) { sh.scrollTo(sh.at() + d * sh.stepPx) })
        }
    }
    // Under the part: a press pages toward the pointer, a drag carries the view along (the part's arrows stay its own:
    // its MouseAreas sit above this one).
    MouseArea {
        id: drag
        anchors.fill: parent
        z: -1
        enabled: sh.shown
        hoverEnabled: true
        property real from: 0
        property real start: 0
        onPressed: mouse => {
            from = sh.vert ? mouse.y : mouse.x
            start = sh.at()
            var len = sh.vert ? height : width
            var thumbAt = len * (sh.content > 0 ? start / sh.content : 0)
            var thumbLen = len * Math.min(1, sh.view / Math.max(1, sh.content))
            if (from < thumbAt) sh.scrollTo(start - sh.view)
            else if (from > thumbAt + thumbLen) sh.scrollTo(start + sh.view)
            start = sh.at()
        }
        onPositionChanged: mouse => {
            if (!pressed) return
            var len = sh.vert ? height : width
            var d = (sh.vert ? mouse.y : mouse.x) - from
            sh.scrollTo(start + d * sh.content / Math.max(1, len))
        }
    }
}
