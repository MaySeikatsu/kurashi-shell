import QtQuick
import QtQuick.Effects
import Quickshell
import "../../core"
import "../../core/motion"
import ".."

// Your animations (W59.7; brief docs/ux/motion-engine.md §5 "Recipes", §8): every recipe the motion packs define, as the
// daemon publishes it (`motion.recipe.<id>`: label, pack, file, tracks, flags, and why it is skipped). A recipe that works
// is a form like any other — the pickers above list it (`motion.forms` offers) —; here it says where it comes from, where
// it is in use, whether reduce motion skips it, and plays on demand in a small preview drawn by the frontend's own
// forms/Recipe.qml (the same frames as on the shell). A skipped recipe lists each reason in words, with the file to open.
// Ma: nothing moves until Play is pressed (or the scrubber dragged); the preview's Driver runs only while it moves.
Column {
    id: rl
    objectName: "recipe-list"
    spacing: Theme.gap
    signal openKey(string key)

    readonly property var tokens: { Store.theme; return (Store.theme && Store.theme.tokens) || ({}) }
    // [{id, t}] in id order; the working ones first.
    readonly property var recipes: {
        var out = []
        for (var k in rl.tokens) {
            if (k.indexOf("motion.recipe.") !== 0) continue
            var t = rl.tokens[k]
            if (t && typeof t === "object") out.push({ id: k.substring(14), t: t })
        }
        out.sort(function (a, b) {
            if ((a.t.ok === true) !== (b.t.ok === true)) return a.t.ok === true ? -1 : 1
            return a.id < b.id ? -1 : a.id > b.id ? 1 : 0
        })
        return out
    }
    // Where the user's packs live, as the daemon reads them (kurashi_motion::pack::user_dir).
    readonly property string dir: {
        var x = Quickshell.env("XDG_CONFIG_HOME")
        return (x && x.charAt(0) === "/" ? x : "~/.config") + "/kurashi/motion/"
    }
    readonly property bool reduce: { Store.config; return Store.valueOf("a11y.reduce_motion", "") === true }
    readonly property var surfaces: ["island", "panel", "peek", "launcher", "centre", "toast", "sidebar", "dock", "bar",
                                     "osd", "menu", "dialog"]

    function label(t, id) { var l = t && t.label ? String(t.label) : id; return I18n.tr(l) }
    // A diagnostic in words: its key's sentence with its arguments; a curve's own reason translated in place.
    function diagText(d) {
        var a = {}
        var args = d.args || {}
        for (var k in args) a[k] = args[k]
        if (typeof a.error === "string") a.error = I18n.fmt(a.error, { key: a.curve !== undefined ? a.curve : "" })
        return I18n.fmt(d.key, a)
    }
    function propsText(t) {
        var names = (t.tracks || []).map(function (x) { return I18n.tr("motion.ui.recipe.prop." + x.prop) })
        return I18n.fmt("motion.ui.recipe.tracks", { props: names.join(I18n.tr("motion.ui.recipe.sep")) })
    }
    // Where the form in effect is this recipe (the daemon's resolved forms per surface and direction).
    function inUse(id) {
        var out = []
        ;["open", "close"].forEach(function (d) {
            var on = rl.surfaces.filter(function (s) { return rl.tokens["motion.form." + s + "." + d] === id })
            // Every surface at once reads as one phrase, not twelve.
            if (on.length === rl.surfaces.length) out.push(I18n.tr("motion.ui.recipe.where_all_" + d))
            else on.forEach(function (s) {
                out.push(I18n.fmt("motion.ui.recipe.where_" + d, { surface: I18n.tr("motion.surface." + s) }))
            })
        })
        return out
    }

    MotionText { width: parent.width; font.weight: Font.DemiBold; text: I18n.tr("motion.ui.recipe.title") }
    MotionText {
        width: parent.width
        small: true
        color: Theme.dim
        text: I18n.fmt(rl.recipes.length === 0 ? "motion.ui.recipe.empty" : "motion.ui.recipe.help", { dir: rl.dir })
        objectName: rl.recipes.length === 0 ? "recipe-empty" : "recipe-help"
    }

    Repeater {
        model: rl.recipes
        delegate: RoundBox {
            id: card
            required property var modelData
            required property int index
            readonly property var t: modelData.t
            readonly property string rid: modelData.id
            readonly property bool ok: t.ok === true
            readonly property string name: rl.label(t, rid)
            readonly property var used: ok ? rl.inUse(rid) : []
            readonly property bool vestibular: !!t.flags && Array.prototype.indexOf.call(t.flags, "vestibular") >= 0
            // Under reduce motion a recipe that turns or zooms a lot does not play here either (the scrubber still shows
            // any frame, by hand).
            readonly property bool mayPlay: !(card.vestibular && rl.reduce)
            objectName: "recipe:" + rid
            width: rl.width
            implicitHeight: Math.max(info.implicitHeight, stage.visible ? stage.height : 0) + 2 * Theme.pad
            radius: Theme.rSm
            color: Theme.container
            border.width: 1
            border.color: card.ok ? Theme.outline : Theme.accent
            Accessible.role: Accessible.Grouping
            Accessible.name: card.name

            // --- the preview: a card hanging under a bar, drawn through forms/Recipe.qml ---
            Item {
                id: stage
                visible: card.ok
                x: Theme.pad
                y: Theme.pad
                width: 132
                height: 104
                clip: true
                Accessible.role: Accessible.Animation
                Accessible.name: I18n.fmt("motion.ui.recipe.preview", { name: card.name })
                // The bar it hangs from, over the card (a card leaving upward goes behind it).
                Rectangle { z: 1; width: parent.width; height: 6; color: Theme.containerHigh }
                Item {
                    id: ph
                    objectName: "recipe-preview:" + card.rid
                    // The host Recipe.qml reads (FormHost's names): the recipe, its progress, the edge it comes from.
                    readonly property var recipe: card.t
                    property real scrubP: -1
                    readonly property real progress: scrubP >= 0 ? scrubP : drv.value
                    readonly property string edge: "top"
                    readonly property rect origin: Qt.rect(0, 0, 0, 0)
                    x: 16
                    y: 6
                    width: 100
                    height: 66
                    Loader {
                        id: fl
                        active: card.ok
                        Component.onCompleted: fl.setSource(Qt.resolvedUrl("forms/Recipe.qml"),
                                                            { host: ph })
                    }
                    readonly property QtObject f: fl.item
                    opacity: f ? f.opacity : 1
                    transform: [
                        Translate { x: ph.f ? ph.f.tx : 0; y: ph.f ? ph.f.ty : 0 },
                        Scale { origin.x: ph.width / 2; origin.y: ph.height / 2; xScale: ph.f ? ph.f.sx : 1; yScale: ph.f ? ph.f.sy : 1 },
                        Rotation {
                            origin.x: ph.f ? ph.f.rx : 0
                            origin.y: ph.f ? ph.f.ry : 0
                            axis { x: ph.f ? ph.f.ax : 0; y: ph.f ? ph.f.ay : 1; z: 0 }
                            angle: ph.f ? ph.f.angle : 0
                        },
                        Matrix4x4 { matrix: ph.f && ph.f.matrix !== undefined ? ph.f.matrix : Qt.matrix4x4() }
                    ]
                    layer.enabled: f ? f.layered : false
                    layer.effect: MultiEffect {
                        readonly property real bm: ph.f && ph.f.blurMax !== undefined ? ph.f.blurMax : 24
                        blurEnabled: bm > 0
                        blurMax: Math.max(1, Math.round(bm))
                        blur: ph.f ? ph.f.blur : 0
                        maskEnabled: !!(ph.f && ph.f.mask)
                        maskSource: ph.f && ph.f.mask ? ph.f.mask : null
                    }
                    // The sample card: a title line and two of text.
                    RoundBox {
                        anchors.fill: parent
                        radius: Theme.rSm
                        color: Theme.containerHigh
                        border.width: 1
                        border.color: Theme.outline
                        Column {
                            x: 10
                            y: 10
                            spacing: 6
                            Rectangle { width: 50; height: 6; radius: 3; color: Theme.accent }
                            Rectangle { width: 72; height: 4; radius: 2; color: Theme.dim }
                            Rectangle { width: 60; height: 4; radius: 2; color: Theme.dim }
                        }
                    }
                }
                Driver {
                    id: drv
                    curves: Theme.motionCurves
                    to: 1
                }
            }
            Column {
                id: info
                x: card.ok ? stage.x + stage.width + Theme.pad : Theme.pad
                y: Theme.pad
                width: card.width - x - Theme.pad
                spacing: Theme.gap / 2
                MotionText { width: parent.width; font.weight: Font.DemiBold; text: card.name }
                MotionText {
                    width: parent.width
                    small: true
                    color: Theme.dim
                    text: I18n.fmt(card.t.path ? "motion.ui.recipe.from_pack" : "motion.ui.recipe.built_in",
                                   { pack: card.t.pack || "" }) + (card.t.path ? " · " + card.t.path : "")
                }
                // Working: what it animates, what it is built on, where it is in use, and what reduce motion does with it.
                MotionText {
                    visible: card.ok
                    width: parent.width
                    small: true
                    text: rl.propsText(card.t) + (card.t.base ? " " + I18n.fmt("motion.ui.recipe.base",
                        { base: I18n.tr("config.choice.motion.form." + card.t.base) }) : "")
                }
                MotionText {
                    visible: card.ok
                    objectName: "recipe-state:" + card.rid
                    width: parent.width
                    small: true
                    text: card.used.length > 0 ? I18n.fmt("motion.ui.recipe.in_use", { where: card.used.join(I18n.tr("motion.ui.recipe.sep")) })
                                               : I18n.tr("motion.ui.recipe.ok")
                }
                MotionText {
                    visible: card.ok && card.vestibular
                    objectName: "recipe-vestibular:" + card.rid
                    width: parent.width
                    small: true
                    color: Theme.dim
                    text: "◐ " + I18n.tr("motion.ui.recipe.vestibular")
                }
                MotionText {
                    visible: card.ok && card.t.layer === true
                    width: parent.width
                    small: true
                    color: Theme.dim
                    text: I18n.tr("motion.ui.recipe.layer")
                }
                // Skipped: every reason, in the order the file has them.
                MotionText {
                    visible: !card.ok
                    objectName: "recipe-skipped:" + card.rid
                    width: parent.width
                    small: true
                    text: "⊘ " + I18n.tr("motion.ui.recipe.skipped")
                }
                Repeater {
                    model: card.ok ? [] : (card.t.diags || [])
                    delegate: MotionText {
                        required property var modelData
                        required property int index
                        objectName: "recipe-diag:" + card.rid + ":" + index
                        width: info.width
                        small: true
                        leftPadding: Theme.gap
                        text: "• " + rl.diagText(modelData)
                    }
                }
                Flow {
                    width: parent.width
                    spacing: Theme.gap
                    Button {
                        visible: card.ok
                        objectName: "recipe-play-open:" + card.rid
                        label: I18n.tr("motion.ui.recipe.play_open")
                        accessibleName: I18n.fmt("motion.ui.recipe.play_name", { action: label, name: card.name })
                        enabled: card.mayPlay
                        onClicked: { ph.scrubP = -1; drv.snap(0); drv.go(1) }
                    }
                    Button {
                        visible: card.ok
                        objectName: "recipe-play-close:" + card.rid
                        label: I18n.tr("motion.ui.recipe.play_close")
                        accessibleName: I18n.fmt("motion.ui.recipe.play_name", { action: label, name: card.name })
                        enabled: card.mayPlay
                        onClicked: { ph.scrubP = -1; drv.snap(1); drv.go(0) }
                    }
                    // The pack file in the user's editor (a built-in pack has none to open).
                    LinkText {
                        visible: !!card.t.path
                        anchors.verticalCenter: undefined
                        height: Theme.controlH
                        objectName: "recipe-open:" + card.rid
                        text: I18n.tr("motion.ui.recipe.open_file")
                        Accessible.name: I18n.fmt("motion.ui.recipe.open_file_name", { name: card.name })
                        onActivated: Qt.openUrlExternally("file://" + card.t.path)
                    }
                }
                // Scrub: any frame between closed (0) and open (1), by drag or the arrow keys (it holds the preview there
                // until Play is pressed again).
                Slider {
                    id: scrub
                    visible: card.ok
                    objectName: "recipe-scrub:" + card.rid
                    width: Math.min(320, info.width)
                    from: 0
                    to: 1
                    step: 0.05
                    value: ph.progress
                    label: I18n.fmt("motion.ui.recipe.scrub", { name: card.name })
                    onPreviewed: v => ph.scrubP = v
                    onCommitted: v => ph.scrubP = v
                    onCancelled: ph.scrubP = -1
                }
            }
        }
    }
}
