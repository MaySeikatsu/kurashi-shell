import QtQuick
import "../../core"
import ".."
import "curvemath.js" as CM
import "reasons.js" as RS

// The `curve` control (schema control "curve", K83; brief docs/ux/motion-engine.md §4, §8): one role's curve
// (theme.motion.timing.<role>) as a graph, in four tabs — Cubic (two handles), Spring (duration and bounce, stiffness and
// damping under Advanced, the response plot), Steps, Presets — and a paste field that takes what people bring from
// elsewhere (cubic-bezier(…), easings.net names, spring(…), Hyprland's x0, y0, x1, y1). What is written is the canonical
// form (curvemath.js reads the value as kurashid does); the daemon judges it, and a refusal shows under the row with its
// reason while nothing is applied. `""` is the profile's curve: the graph draws the curve in effect and the line under it
// names the profile and where the profile comes from. A picker (SettingRow.picker): it reads and sets its own value.
Column {
    id: cc
    // Set by SettingRow (a picker knows its key).
    property string rowKey: ""
    signal openKey(string key)
    objectName: "curve:" + cc.rowKey
    spacing: Theme.gap

    readonly property var row: { Store.schema; var h = Store.rowOf(cc.rowKey); return h ? h.row : ({}) }
    readonly property string role: cc.rowKey.substring(cc.rowKey.lastIndexOf(".") + 1)
    readonly property string label: cc.row.label ? I18n.tr(cc.row.label) : cc.rowKey
    readonly property var prov: { Store.config; return Store.prov(cc.rowKey, "") }
    readonly property string value: cc.prov && typeof cc.prov.value === "string" ? cc.prov.value : ""
    // As SettingRow decides it: a pending restart, a missing offer or a mod that is off keep a row editable.
    // The daemon's own reason (K83: motion off, …) when Store.inertReasons does not word it: shown here, and inert.
    readonly property var own: RS.extra(cc.prov)
    readonly property bool inert: { Store.config; return cc.own !== null || Store.inertReasons(cc.row, "").some(function (x) {
        return x.kind !== "pending" && x.kind !== "unavailable" && x.kind !== "mod_off" }) }
    readonly property bool editable: !cc.inert && Store.live
    readonly property bool refused: !!Store.rowErrors[cc.rowKey]

    MotionReason { reason: cc.own; onOpenKey: key => cc.openKey(key) }

    // The value read as the daemon reads it (a pack's curve name has no curve here: its pack has it).
    readonly property var parsed: cc.value === "" ? null : CM.parse(cc.value)
    // The curve the profile gives this role, from the theme document (W59.1's tokens, else today's).
    readonly property var profiles: { Store.theme; return CM.inEffect(Store.theme.tokens, cc.role) }
    // The curve in effect: the user's when it reads, else the profile's.
    readonly property var effective: cc.parsed && cc.parsed.ok && cc.parsed.curve ? cc.parsed.curve
        : (cc.profiles ? cc.profiles.curve : null)
    // The duration: the role's own (theme.motion.timing.<role>_ms), else the preset's, else the profile's.
    readonly property int ownMs: { Store.config; var v = Store.valueOf(cc.rowKey + "_ms", ""); return typeof v === "number" ? v : 0 }
    readonly property real ms: cc.ownMs > 0 ? cc.ownMs
        : (cc.parsed && cc.parsed.ms ? cc.parsed.ms : (cc.profiles && cc.profiles.ms ? cc.profiles.ms : 500))

    // --- drafts: a handle moved, not committed yet (Return or the pointer's release commits, Escape reverts) ------------
    property var draft: null
    onValueChanged: cc.draft = null
    onRefusedChanged: if (cc.refused) cc.draft = null
    readonly property var shown: cc.draft ? ({ kind: "cubic", points: cc.draft.concat([1, 1]) }) : cc.effective

    function write(text) {
        if (!cc.editable) return
        if (text === cc.value) return
        Store.setValue(cc.rowKey, text, "")
    }
    // Typed or pasted text: written canonical when it reads; otherwise as typed, so the daemon's reason is the one shown.
    function submit(text) {
        var t = text.trim()
        if (t === "") { if (cc.value !== "") Store.reset(cc.rowKey, ""); return }
        var p = CM.parse(t)
        cc.write(p.ok ? CM.canonical(p) : t)
    }
    function commitDraft() {
        if (!cc.draft) return
        var c = { kind: "cubic", points: cc.draft.concat([1, 1]) }
        cc.write(CM.canonicalCurve(c))
    }

    // --- the tab on show: the kind of the curve in effect until another is opened --------------------------------------
    readonly property string kindTab: !cc.effective ? "cubic"
        : cc.effective.kind === "spring" ? "spring" : cc.effective.kind === "steps" ? "steps"
        : "cubic"
    property string tab: ""
    readonly property string openTab: cc.tab !== "" ? cc.tab : cc.kindTab
    readonly property var tabs: [
        { id: "cubic", label: I18n.tr("motion.ui.curve.tab.cubic") },
        { id: "spring", label: I18n.tr("motion.ui.curve.tab.spring") },
        { id: "steps", label: I18n.tr("motion.ui.curve.tab.steps") },
        { id: "presets", label: I18n.tr("motion.ui.curve.tab.presets") }
    ]
    // What the Spring and Steps tabs start from when the curve in effect is of another kind: the fluid preset, 6 steps.
    readonly property bool isSpring: !!cc.effective && cc.effective.kind === "spring"
    readonly property real springResponse: cc.isSpring ? cc.effective.response : 500
    readonly property real springBounce: cc.isSpring ? cc.effective.bounce : 0.25
    readonly property bool isSteps: !!cc.effective && cc.effective.kind === "steps"
    readonly property int stepsN: cc.isSteps ? cc.effective.n : 6
    // A cubic with several segments has no handles: a preset or a paste edits it (or a handle drag starts one cubic).
    readonly property bool segmented: !!cc.effective && cc.effective.kind === "cubic" && cc.effective.points.length > 6

    function writeSpring(response, bounce) {
        var r = Math.max(CM.SPRING_MS_MIN, Math.min(CM.SPRING_MS_MAX, Math.round(response)))
        var b = Math.max(CM.BOUNCE_MIN, Math.min(CM.BOUNCE_MAX, Math.round(bounce * 100) / 100))
        cc.write(CM.canonicalCurve({ kind: "spring", response: r, bounce: b }))
    }

    // --- provenance in words: whose curve this is (brief §3: "from profile Origami (style Kami)") ----------------------
    readonly property string profileId: { Store.theme; var t = Store.theme.tokens; return t && t["motion.profile"] ? t["motion.profile"] : "" }
    readonly property string profileName: cc.profileId === "" ? "" : (I18n.has("config.choice.motion.profile." + cc.profileId)
        ? I18n.tr("config.choice.motion.profile." + cc.profileId) : cc.profileId)
    readonly property string profileSource: { Store.config; var p = Store.prov("theme.motion.profile", "")
        return p && p.source ? Store.sourceName("theme.motion.profile", p.source) : "" }
    // A curve by name when it is a preset ("Expressive"), else in its canonical form.
    function nameOf(c) {
        if (!c) return I18n.tr("motion.ui.curve.none")
        if (c.kind === "spring_q") {
            for (var i = 0; i < CM.PRESETS.length; i++) {
                var q = CM.PRESETS[i].curve
                if (q.kind === "spring_q" && q.spring === c.spring && q.damping === c.damping)
                    return I18n.tr("config.choice.curve." + CM.PRESETS[i].id)
            }
            return I18n.tr("motion.ui.curve.own_spring")
        }
        var text = CM.canonicalCurve(c)
        for (var j = 0; j < CM.PRESETS.length; j++)
            if (CM.PRESETS[j].curve.kind !== "spring_q" && CM.canonicalCurve(CM.PRESETS[j].curve) === text)
                return I18n.tr("config.choice.curve." + CM.PRESETS[j].id)
        return text
    }
    readonly property string whose: {
        var tr = I18n.strings
        var profiles = cc.profiles ? cc.nameOf(cc.profiles.curve) : I18n.tr("motion.ui.curve.none")
        var from = I18n.fmt("motion.ui.profile_source", { profile: cc.profileName, source: cc.profileSource })
        if (cc.value === "") return I18n.fmt("motion.ui.curve.from_profile", { curve: profiles, from: from })
        if (cc.parsed && cc.parsed.ok && cc.parsed.type === "named")
            return I18n.fmt("motion.ui.curve.named", { name: cc.value })
        return I18n.fmt("motion.ui.curve.yours", { curve: profiles, profile: cc.profileName })
    }

    // --- the tabs and their views -------------------------------------------------------------------------------------
    MotionTabs {
        tabs: cc.tabs
        current: cc.openTab
        prefix: "curve-tab:" + cc.rowKey
        onActivated: id => cc.tab = id
    }

    Flow {
        width: parent.width
        spacing: Theme.pad
        opacity: cc.editable ? 1 : 0.5

        // Cubic and Steps draw on the graph; Spring on its plot; Presets on its tiles.
        CurveGraph {
            id: graph
            visible: cc.openTab === "cubic" || cc.openTab === "steps"
            key: cc.rowKey
            label: cc.label
            ms: cc.ms
            curve: cc.openTab === "steps" ? ({ kind: "steps", n: cc.stepsN }) : cc.shown
            editable: cc.editable && cc.openTab === "cubic"
            onMoved: points => cc.draft = points.slice(0, 4)
            onCommit: cc.commitDraft()
            onRevert: cc.draft = null
            Accessible.role: Accessible.Graphic
            Accessible.name: I18n.fmt("motion.ui.curve.graph", { name: cc.label, curve: cc.nameOf(graph.curve) })
        }
        SpringPlot {
            id: plot
            visible: cc.openTab === "spring"
            key: cc.rowKey
            label: cc.label
            response: cc.springResponse
            bounce: cc.springBounce
        }
        CurvePresets {
            visible: cc.openTab === "presets"
            width: Math.min(cc.width, 520)
            key: cc.rowKey
            current: cc.value === "" ? "" : (cc.parsed && cc.parsed.ok && cc.parsed.type === "preset" ? cc.parsed.id : "")
            enabled: cc.editable
            onPicked: id => cc.write(id)
        }

        // Beside the graph: what is drawn in words, and the tab's own controls.
        Column {
            visible: cc.openTab !== "presets"
            width: Math.max(200, Math.min(300, cc.width - graph.width - Theme.pad))
            spacing: Theme.gap

            MotionText {
                objectName: "curve-text:" + cc.rowKey
                width: parent.width
                font.family: "monospace"
                small: true
                text: cc.openTab === "spring" ? CM.canonicalCurve(plot.curve)
                    : cc.openTab === "steps" ? "steps(" + cc.stepsN + ")"
                    : (cc.shown ? cc.nameOf(cc.shown) : I18n.tr("motion.ui.curve.none"))
            }
            // A draft says so, and how to keep or drop it (keyboard and pointer alike).
            MotionText {
                visible: cc.draft !== null
                width: parent.width
                small: true
                color: Theme.dim
                text: I18n.tr("motion.ui.curve.draft")
            }
            MotionText {
                visible: cc.openTab === "cubic" && cc.segmented && cc.draft === null
                width: parent.width
                small: true
                color: Theme.dim
                text: I18n.tr("motion.ui.curve.segments")
            }
            MotionText {
                visible: cc.openTab === "spring" && !cc.isSpring || cc.openTab === "steps" && !cc.isSteps
                width: parent.width
                small: true
                color: Theme.dim
                text: I18n.tr("motion.ui.curve.start_point")
            }
            // Spring: duration (the response) and bounce; stiffness and damping under Advanced.
            Column {
                visible: cc.openTab === "spring"
                width: parent.width
                spacing: 2
                MotionText { small: true; color: Theme.dim; text: I18n.tr("motion.ui.spring.duration") }
                Slider {
                    objectName: "spring-duration:" + cc.rowKey
                    width: parent.width
                    label: I18n.tr("motion.ui.spring.duration")
                    from: CM.SPRING_MS_MIN
                    to: CM.SPRING_MS_MAX
                    step: 10
                    integer: true
                    unit: "ms"
                    value: cc.springResponse
                    enabled: cc.editable
                    cancellable: false
                    onCommitted: v => cc.writeSpring(v, cc.springBounce)
                }
                MotionText { small: true; color: Theme.dim; text: I18n.tr("motion.ui.spring.bounce") }
                Slider {
                    objectName: "spring-bounce:" + cc.rowKey
                    width: parent.width
                    label: I18n.tr("motion.ui.spring.bounce")
                    from: CM.BOUNCE_MIN
                    to: CM.BOUNCE_MAX
                    step: 0.05
                    value: cc.springBounce
                    enabled: cc.editable
                    cancellable: false
                    onCommitted: v => cc.writeSpring(cc.springResponse, v)
                }
                LinkText {
                    text: I18n.tr(adv.open ? "motion.ui.spring.advanced_hide" : "motion.ui.spring.advanced")
                    onActivated: adv.open = !adv.open
                }
                Column {
                    id: adv
                    property bool open: false
                    readonly property var params: CM.springParams(cc.springResponse, cc.springBounce)
                    visible: open
                    width: parent.width
                    spacing: 2
                    MotionText { small: true; color: Theme.dim; text: I18n.tr("motion.ui.spring.stiffness") }
                    TextField {
                        objectName: "spring-stiffness:" + cc.rowKey
                        width: parent.width
                        label: I18n.tr("motion.ui.spring.stiffness")
                        mono: true
                        value: adv.params.stiffness.toFixed(1)
                        enabled: cc.editable
                        onAccepted: t => { var k = Number(t); if (k > 0) { var s = CM.fromStiffness(k, adv.params.damping); cc.writeSpring(s.response, s.bounce) } }
                    }
                    MotionText { small: true; color: Theme.dim; text: I18n.tr("motion.ui.spring.damping") }
                    TextField {
                        objectName: "spring-damping:" + cc.rowKey
                        width: parent.width
                        label: I18n.tr("motion.ui.spring.damping")
                        mono: true
                        value: adv.params.damping.toFixed(2)
                        enabled: cc.editable
                        onAccepted: t => { var d = Number(t); if (d > 0) { var s = CM.fromStiffness(adv.params.stiffness, d); cc.writeSpring(s.response, s.bounce) } }
                    }
                    MotionText {
                        width: parent.width
                        small: true
                        color: Theme.dim
                        text: I18n.tr("motion.ui.spring.advanced_help")
                    }
                }
            }
            // Steps: how many held frames.
            Column {
                visible: cc.openTab === "steps"
                width: parent.width
                spacing: 2
                MotionText { small: true; color: Theme.dim; text: I18n.tr("motion.ui.steps.count") }
                Slider {
                    objectName: "steps-count:" + cc.rowKey
                    width: parent.width
                    label: I18n.tr("motion.ui.steps.count")
                    from: CM.STEPS_MIN
                    to: CM.STEPS_MAX
                    step: 1
                    integer: true
                    value: cc.stepsN
                    enabled: cc.editable
                    cancellable: false
                    onCommitted: v => cc.write("steps(" + Math.round(v) + ")")
                }
            }
            Button {
                objectName: "curve-play:" + cc.rowKey
                label: I18n.tr("motion.ui.curve.play")
                accessibleName: I18n.fmt("motion.ui.curve.play_name", { name: cc.label })
                enabled: cc.openTab === "spring" || (!!graph.curve && graph.curve.kind !== "spring_q")
                onClicked: cc.openTab === "spring" ? plot.play() : graph.play()
            }
        }
    }

    // Paste: any notation the daemon reads. Return applies; a refusal keeps the text and the row says why.
    Row {
        width: parent.width
        spacing: Theme.gap
        TextField {
            id: paste
            objectName: "curve-paste:" + cc.rowKey
            width: Math.min(parent.width, 420)
            label: I18n.fmt("motion.ui.curve.paste_name", { name: cc.label })
            placeholder: I18n.tr("motion.ui.curve.paste_hint")
            mono: true
            value: cc.value
            enabled: cc.editable
            invalid: cc.refused
            onAccepted: t => cc.submit(t)
        }
    }
    MotionText {
        objectName: "curve-whose:" + cc.rowKey
        width: parent.width
        small: true
        color: Theme.dim
        text: cc.whose
    }
    // Save as preset… needs a daemon intent that writes a user motion pack (CONTRACT-CHANGE, W59.6): inert, with why.
    Row {
        spacing: Theme.gap
        Button {
            objectName: "curve-save:" + cc.rowKey
            label: I18n.tr("motion.ui.curve.save")
            enabled: false
        }
        MotionText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, cc.width - 160)
            small: true
            color: Theme.dim
            text: "⊘ " + I18n.tr("motion.ui.curve.save_unavailable")
        }
    }
}
