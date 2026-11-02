import QtQuick
import QtQuick.Effects
import "../../core"

// FormHost (K83, docs/ux/motion-engine.md §5, §9; W59 contract "Frontend interfaces"): the form a surface opens and
// closes in, drawn from one progress. A surface puts its content inside and drives `progress` (0 gone … 1 in place;
// past 1 while a curve overshoots) from its own Driver or morph; FormHost picks the form from the tokens
// (`Theme.motionForm(surface, direction)`) and **latches** it when a transition starts (progress leaves 0 or 1), so a
// reversal mid-way continues the form in flight and a token change lands on the next transition. By family:
//   shape      (grow; later expand, iris, stamp, outline, liquid, drop): the silhouette is the morph's (MorphSprings,
//              MorphShape): FormHost only names the form, the content is left alone;
//   transform  (slide, rubber, zoom, fade, flip, bleed, stepped): a small object from `forms/<Form>.qml` (TransformForm)
//              yields opacity, translate, scale, rotation and blur, and FormHost applies them to itself — plain
//              properties, a layer only for bleed while it shows;
//   sheet      (fold, roll, book, crumple, genie, crt …; W59.4+): `forms/<Form>.qml` (a SheetForm) is loaded only while
//              0 < p < 1 and gets {source, progress, edge, origin, params, size, direction, surface, form}; it captures
//              `source` (the content) into its own layer and draws it warped. A sheet form whose meta says it is not
//              available, or whose component fails to load, falls back to fade (logged once).
// Nothing runs at rest: no timers, no layer, no loaded sheet (Ma). Today's Entrance is a thin wrapper of this.
Item {
    id: host
    // The surface class (island panel peek launcher centre toast sidebar dock bar osd menu dialog).
    property string surface: "panel"
    // Where the surface comes from: "top", "bottom", "left" or "right" (its edge; a sheet's hinge).
    property string edge: "top"
    // The origin (the pressed module's rect, in host coordinates); empty = none (the bar's centre is the surface's
    // business).
    property rect origin: Qt.rect(0, 0, 0, 0)
    property real progress: 1
    // "open", "close", or "auto": opening when the transition starts from 0, closing from 1.
    property string direction: "auto"
    // What a sheet form captures: the content, unless the surface names another item.
    property Item source: body
    default property alias content: body.data

    // The direction and form of the transition in flight; at rest the ones the next transition will take.
    readonly property bool busy: progress !== 0 && progress !== 1
    property real lastRest: 1
    property string latchedForm: ""
    property string latchedDir: ""
    readonly property string nextDir: direction !== "auto" ? direction : (lastRest >= 1 ? "close" : "open")
    readonly property string dir: busy && latchedDir !== "" ? latchedDir : nextDir
    readonly property string form: busy && latchedForm !== "" ? latchedForm : Theme.motionForm(surface, nextDir)
    readonly property var meta: Theme.formMeta(form)
    readonly property string family: form === "" || form === "none" ? "none" : (meta ? meta.family : "transform")
    readonly property var params: Theme.formParams(form)
    onBusyChanged: {
        if (busy) { latchedDir = nextDir; latchedForm = Theme.motionForm(surface, latchedDir) }
        else { lastRest = progress >= 1 ? 1 : 0; latchedForm = ""; latchedDir = "" }
    }
    Component.onCompleted: {
        if (!busy) lastRest = progress >= 1 ? 1 : 0
        loadTransform()
        checkForm()
    }

    // --- transform forms ---
    readonly property var transforms: ({ slide: "Slide", rubber: "Slide", zoom: "Zoom", fade: "Fade", flip: "Flip",
        bleed: "Bleed", stepped: "Stepped" })
    property var failed: ({})
    readonly property bool sheetOk: family === "sheet" && meta && meta.available !== false && !failed[form]
    readonly property string transformComp: family === "shape" || family === "none" || sheetOk ? ""
        : family === "sheet" ? "Fade" : (transforms[form] || "Fade")
    onTransformCompChanged: loadTransform()
    onFormChanged: checkForm()
    function checkForm() {
        if (transformComp === "Fade" && form !== "fade")
            warnOnce(form, family === "sheet" ? "is not available" : "has no component")
    }
    property var warned: ({})
    function warnOnce(f, why) {
        if (warned[f]) return
        warned[f] = true
        console.log("motion: form " + f + " " + why + " on " + surface + ", fading")
    }
    function loadTransform() {
        if (transformComp === "") { tf.active = false; tf.source = ""; return }
        tf.active = true
        tf.setSource(Qt.resolvedUrl("forms/" + transformComp + ".qml"), { host: host })
    }
    Loader { id: tf; active: false }
    readonly property QtObject f: tf.item
    opacity: f ? f.opacity : 1
    transform: [
        Translate { x: host.f ? host.f.tx : 0; y: host.f ? host.f.ty : 0 },
        Scale {
            origin.x: host.width / 2
            origin.y: host.height / 2
            xScale: host.f ? host.f.sx : 1
            yScale: host.f ? host.f.sy : 1
        },
        Rotation {
            origin.x: host.f ? host.f.rx : 0
            origin.y: host.f ? host.f.ry : 0
            axis { x: host.f ? host.f.ax : 0; y: host.f ? host.f.ay : 1; z: 0 }
            angle: host.f ? host.f.angle : 0
        }
    ]
    layer.enabled: f ? f.layered : false
    layer.effect: MultiEffect {
        blurEnabled: true
        blurMax: 24
        blur: host.f ? host.f.blur : 0
    }

    // --- the content ---
    Item { id: body; anchors.fill: parent }

    // --- sheet forms (W59.4+) ---
    function pascal(n) {
        return n.split("-").map(function (w) { return w.charAt(0).toUpperCase() + w.slice(1) }).join("")
    }
    Loader {
        id: sheet
        anchors.fill: parent
        active: host.sheetOk && host.busy
        source: active ? Qt.resolvedUrl("forms/" + host.pascal(host.form) + ".qml") : ""
        // (live, without a Binding object per property at rest: set once the sheet exists)
        onLoaded: {
            item.source = Qt.binding(function () { return host.source })
            item.progress = Qt.binding(function () { return host.progress })
            item.edge = Qt.binding(function () { return host.edge })
            item.origin = Qt.binding(function () { return host.origin })
            item.params = Qt.binding(function () { return host.params })
            item.size = Qt.binding(function () { return Qt.size(host.width, host.height) })
            item.direction = Qt.binding(function () { return host.dir })
            item.surface = Qt.binding(function () { return host.surface })
            item.form = Qt.binding(function () { return host.form })
        }
        onStatusChanged: if (status === Loader.Error) {
            var m = Object.assign({}, host.failed)
            m[host.form] = true
            host.failed = m
            host.warnOnce(host.form, "failed to load")
        }
    }
}
