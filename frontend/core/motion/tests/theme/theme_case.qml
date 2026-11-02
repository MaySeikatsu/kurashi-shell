import QtQuick
import QtTest

// The Theme's motion readers (W59.2) with today's tokens only (a daemon before W59.1: derived) and with W59.1's.
// test-motion.sh copies this as tst_theme.qml beside a copy of core/Theme.qml and the Store stand-in (theme/), then runs
// it offscreen with the Quickshell stub (`-import tests/stub`).
TestCase {
    name: "theme"
    function set(t) { Store.docs = { theme: { tokens: t } } }
    readonly property var open: [0.38, 1.21, 0.22, 1, 1, 1]

    function test_derived_timed() {
        set({ "motion.kind": "timed", "motion.timed.open_ms": 500, "motion.timed.open_curve": open,
              "motion.timed.close_ms": 400, "motion.style": "grow" })
        var c = Theme.motionCurve("open")
        compare(c.kind, "cubic")
        compare(c.ms, 500)
        compare(c.points, open)
        compare(Theme.motionCurve("close").ms, 400)
        compare(Theme.motionForm("panel", "open"), "grow")
        compare(Theme.formMeta("grow").family, "shape")
        compare(Theme.formMeta("bleed").family, "transform")
        compare(Theme.formMeta("nope"), null)
        compare(Theme.motionAccent("content"), "late")
        compare(Theme.motionAccent("jelly"), 0)
    }
    function test_derived_stepped_is_a_cubic() {
        set({ "motion.kind": "stepped", "motion.timed.open_ms": 67, "motion.timed.open_curve": [0, 0, 0.001, 1, 0.001, 1, 0.001, 1, 1, 1, 1, 1],
              "motion.style": "stepped" })
        compare(Theme.motionCurve("open").kind, "cubic")
        compare(Theme.motionForm("toast", "close"), "stepped")
    }
    function test_derived_spring() {
        set({ "motion.kind": "spring", "motion.spring.on": true, "motion.spring.spring": 3.2, "motion.spring.damping": 0.26,
              "motion.spring.squash": 0.06 })
        var c = Theme.motionCurve("open")
        compare(c.kind, "spring_q")
        compare(c.spring, 3.2)
        compare(c.damping, 0.26)
        compare(Theme.motionAccent("squash"), 0.06)
        fuzzyCompare(Theme.motionAccent("overshoot_cap"), 0.0794, 1e-9)
    }
    function test_derived_none() {
        set({ "motion.kind": "none", "motion.spring.on": false, "motion.style": "none" })
        compare(Theme.motionCurve("effects").kind, "none")
        compare(Theme.motionForm("island", "open"), "none")
        compare(Theme.motionAccent("squash"), 0)
    }
    function test_w59_tokens_win() {
        set({ "motion.kind": "timed", "motion.style": "grow", "motion.timed.open_curve": open,
              "motion.curve.open": { kind: "spring", ms: 550, response: 550, bounce: 0.45 },
              "motion.form.toast.open": "drop", "motion.form.panel.open": "",
              "motion.form_params.fold": { panels: 3 },
              "motion.accent.jelly": 0.5, "motion.accent.content": "cascade",
              "motion.forms": { fold: { family: "sheet", available: false } } })
        compare(Theme.motionCurve("open").kind, "spring")
        compare(Theme.motionCurve("close").kind, "cubic")   // (no motion.curve.close: derived)
        compare(Theme.motionForm("toast", "open"), "drop")
        compare(Theme.motionForm("panel", "open"), "grow")  // "" = the look's
        compare(Theme.formParams("fold").panels, 3)
        compare(Theme.formParams("roll"), Theme.noParams)
        compare(Theme.motionAccent("jelly"), 0.5)
        compare(Theme.motionAccent("content"), "cascade")
        compare(Theme.formMeta("fold").family, "sheet")
        compare(Theme.formMeta("grow"), null)               // the daemon's table replaces the stand-in
    }
}
