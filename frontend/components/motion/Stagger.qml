import QtQuick
import "../../core"

// Stagger (K83, docs/ux/motion-engine.md §7 "Content"): when a surface's content arrives, from the host's one progress —
// no timers, no animation of its own (Ma). `at(i)` is child i's own progress (0..1); bind a row's opacity or offset to
// it (QML has no attached properties without C++: `opacity: stagger.at(index)`):
//   late     every child fades in once p ≥ 0.6 and out first (today's content);
//   with     every child follows p;
//   cascade  child i arrives after i·s: pᵢ = clamp((p − i·s) / (1 − n·s)), s = stagger_ms / duration (n·s kept ≤ 0.8,
//            so the last child still has a fifth of the travel).
QtObject {
    property real progress: 1
    property int count: 1
    property string content: Theme.motionAccent("content")
    property real staggerMs: Theme.motionAccent("stagger_ms")
    // The duration the progress takes (its curve's `ms`), to turn stagger_ms into a fraction.
    property real durationMs: Theme.motionCurve("open").ms || 0
    readonly property real step: durationMs > 0 && count > 0 ? Math.min(staggerMs / durationMs, 0.8 / count) : 0
    function clamp01(v) { return Math.max(0, Math.min(1, v)) }
    function at(i) {
        var p = progress
        if (content === "with") return clamp01(p)
        if (content === "cascade") return step > 0 ? clamp01((p - i * step) / (1 - count * step)) : clamp01(p)
        return clamp01((p - 0.6) / 0.4)
    }
}
