import QtQuick

// A shape form drawn on a surface that has no morph of its own (K83, W59.3): a dialog, a card that slides from a side
// bar, a toast without a bar, the dock, a sidebar. Put the surface's card inside; give it the surface's SurfaceForm
// (`run`), whose from*/to*/edgeY are in the form's frame — y away from `edge` (the side the surface comes from), x along
// it — in this item's px. While a shape form moves (and only then: a layer, Ma) it draws the card through FormMask:
// expand cut at its foot, iris inside its circle, stamp at its fade and scale (about (cx, `pivotY`)), outline as its
// stepped rects with the card hidden. At rest, and in every other form, it is a plain item: today's frames unchanged.
Item {
    id: sl
    property QtObject run: null
    property string edge: "top"
    // The frame y the stamp scales about (default: the edge the surface comes from).
    property real pivotY: run ? run.edgeY : 0
    default property alias content: inner.data

    readonly property QtObject sf: run && run.mode === "shape" && run.busy ? run.shape : null
    readonly property bool transposed: edge === "left" || edge === "right"
    readonly property bool flipped: edge === "bottom" || edge === "right"
    readonly property real along: transposed ? width : height
    // A point of the frame in this item's px.
    function px(fx, fy) {
        var a = flipped ? along - fy : fy
        return transposed ? Qt.point(a, fx) : Qt.point(fx, a)
    }
    function rectOf(r) {
        var y0 = flipped ? along - r.y - r.h : r.y
        return transposed ? { x: y0, y: r.x, w: r.h, h: r.w, r: r.r, a: r.a } : { x: r.x, y: y0, w: r.w, h: r.h, r: r.r, a: r.a }
    }
    readonly property point pivot: sf ? px(sf.cx, pivotY) : Qt.point(0, 0)

    Item {
        id: masked
        anchors.fill: parent
        layer.enabled: sl.sf !== null
        layer.effect: FormMask {
            form: sl.sf
            keep: -1
            flipped: sl.flipped
            transposed: sl.transposed
            cut: true
        }
        transform: Scale {
            origin.x: sl.pivot.x
            origin.y: sl.pivot.y
            xScale: sl.sf ? (sl.transposed ? sl.sf.sy : sl.sf.sx) : 1
            yScale: sl.sf ? (sl.transposed ? sl.sf.sx : sl.sf.sy) : 1
        }
        Item { id: inner; anchors.fill: parent }
    }
    OutlineRects {
        anchors.fill: parent
        rects: sl.sf && sl.sf.outline ? sl.sf.rects.map(function (r) { return sl.rectOf(r) }) : []
    }
}
