import QtQuick
import QtQuick.Effects
import "../../core"

// FormHost (K83, docs/ux/motion-engine.md §5, §9; W59 contract "Frontend interfaces"): the form a surface opens and
// closes in, drawn from one progress. A surface puts its content inside and drives `progress` (0 gone … 1 in place;
// past 1 while a curve overshoots) from its own Driver or morph; FormHost picks the form from the tokens
// (`Theme.motionForm(surface, direction)`) and **latches** it when a transition starts (progress leaves 0 or 1), so a
// reversal mid-way continues the form in flight and a token change lands on the next transition. What it draws:
//   transform  today's content forms (W53's slide, rubber, zoom, fade, flip, bleed, stepped; the meta files them under
//              `shape`): a small object from `forms/<Form>.qml` (TransformForm) yields opacity, translate, scale,
//              rotation and blur, and FormHost applies them to itself — plain properties, a layer only for bleed while it
//              shows. Keyed on the component (`transforms`), not on the family;
//   shape      the rest of the `shape` family (grow; later expand, iris, stamp, outline, liquid, drop): the silhouette is
//              the morph's (MorphSprings, MorphShape): FormHost only names the form, the content is left alone;
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
    // Where the user pressed (W59.9a, row 658; host coordinates), NaN = no press: a sheet form that starts at a point
    // (drop's bead) reads it when it has a `pressAt` of its own.
    property point pressAt: Qt.point(NaN, NaN)
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
    readonly property string dir: latchedDir !== "" ? latchedDir : nextDir
    readonly property string form: latchedForm !== "" ? latchedForm : Theme.motionForm(surface, nextDir)
    readonly property var meta: Theme.formMeta(form)
    readonly property string family: form === "" || form === "none" ? "none" : (meta ? meta.family : "unknown")
    readonly property var params: Theme.formParams(form)
    onBusyChanged: {
        if (busy) { latchedDir = nextDir; latchedForm = Theme.motionForm(surface, latchedDir) }
        else { lastRest = progress >= 1 ? 1 : 0; Qt.callLater(unlatch) }
    }
    // (I392: after the sheet Loader's `active` has dropped: in the same turn the Loader would make and drop the other
    // direction's form.)
    function unlatch() { if (!busy) { latchedForm = ""; latchedDir = "" } }
    // (row 656: a jump straight from one rest to the other — a cut, motion off, a snap — never passes through busy; the
    // next transition must still take the direction away from where it now rests.)
    // (Tested on the value itself: `busy` may not have re-evaluated yet inside this handler.)
    onProgressChanged: if (progress === 0 || progress === 1) lastRest = progress
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
    // A recipe (W59.7: a user's form from a motion pack, `recipe: true` in the meta): forms/Recipe.qml runs its tracks
    // (`motion.recipe.<id>`) at content level, as a transform form.
    readonly property var recipe: meta && meta.recipe === true ? Theme.tokens["motion.recipe." + form] || null : null
    readonly property string transformComp: recipe ? "Recipe" : transforms[form] !== undefined ? transforms[form]
        : family === "shape" || family === "none" || sheetOk ? "" : "Fade"
    onTransformCompChanged: loadTransform()
    onFormChanged: checkForm()
    // (checked once the form's meta and family have followed it: inside onFormChanged they may still be the last form's,
    // which named `grow` unknown on every surface at start — the lead's finding, W59.9a)
    function checkForm() { Qt.callLater(checkNow) }
    function checkNow() {
        if (transformComp === "Fade" && form !== "fade")
            warnOnce(form, family === "sheet" ? "is not available" : "is unknown")
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
        },
        // A recipe's tracks (scale, skew, turns, translation) as one matrix, after the rest; identity for the others.
        Matrix4x4 { matrix: host.f && host.f.matrix !== undefined ? host.f.matrix : host.identity }
    ]
    readonly property matrix4x4 identity: Qt.matrix4x4()
    // A form may size the blur (a recipe's own px) and mask the layer (a recipe's clip); today's forms: 24, no mask.
    readonly property real blurMaxOf: f && f.blurMax !== undefined ? f.blurMax : 24
    layer.enabled: f ? f.layered : false
    layer.effect: MultiEffect {
        blurEnabled: host.blurMaxOf > 0
        blurMax: Math.max(1, Math.round(host.blurMaxOf))
        blur: host.f ? host.f.blur : 0
        maskEnabled: !!(host.f && host.f.mask)
        maskSource: host.f && host.f.mask ? host.f.mask : null
    }

    // --- the content ---
    // (S21: a sheet form opening from 0 draws nothing until it moves — the card must not show for the frame it is mapped)
    Item { id: body; anchors.fill: parent; visible: !(host.sheetOk && host.progress <= 0 && host.nextDir === "open") }

    // --- sheet forms (W59.4+) ---
    // The handover a surface applies while a sheet form warps its card (row 656, brief §5): its elevation shadow ×
    // `sheetShadow` (out over the first 10 % of a close, in over the last 10 % of an open; the shadow stays OUTSIDE
    // `source`), the join's fillets × `sheetFillets` (in over the last 15 %), a translucent fill drawn solid (the sheet
    // composites it itself) and no compositor blur region while `sheetBlurOff`. 1 / false at rest and for other forms.
    readonly property real sheetShadow: sheet.item && sheet.item.shadowK !== undefined ? sheet.item.shadowK : 1
    readonly property real sheetFillets: sheet.item && sheet.item.filletK !== undefined ? sheet.item.filletK : 1
    readonly property bool sheetSolid: !!sheet.item
    readonly property bool sheetBlurOff: !!sheet.item
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
            if (item.pressAt !== undefined) item.pressAt = Qt.binding(function () { return host.pressAt })
        }
        onStatusChanged: if (status === Loader.Error) {
            var m = Object.assign({}, host.failed)
            m[host.form] = true
            host.failed = m
            host.warnOnce(host.form, "failed to load")
        }
    }
}
