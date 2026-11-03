import QtQuick
import "../../core"
import ".."
import "curvemath.js" as CM

// A spring's response (brief §4, §8): position over time from rest to 1, until it has settled (|x − 1| < 0.001), with its
// overshoot and settle time in words. The spring is the analytic one of §4 (mass 1, response and bounce), computed here
// (curvemath.js) until the daemon's sampled plot is exposed.
Column {
    id: sp
    property real response: 500
    property real bounce: 0.25
    property string key: ""
    property string label: ""
    readonly property var stats: CM.springStats(sp.response, sp.bounce)
    readonly property var curve: ({ kind: "spring", response: sp.response, bounce: sp.bounce })
    function play() { graph.play() }
    spacing: 2

    CurveGraph {
        id: graph
        key: sp.key
        label: sp.label
        curve: sp.curve
        ms: sp.response
        Accessible.role: Accessible.Graphic
        Accessible.name: I18n.fmt("motion.ui.spring.summary", { over: (sp.stats.overshoot * 100).toFixed(1),
                                                             settle: sp.stats.settleMs })
    }
    // Time under the plot: it starts at 0 and runs until the spring has settled.
    Item {
        width: graph.width
        height: tl.implicitHeight
        MotionText { id: tl; x: graph.padL; small: true; color: Theme.dim; text: "0 ms" }
        MotionText {
            x: graph.padL + graph.plotW - implicitWidth
            small: true
            color: Theme.dim
            text: Math.round(Math.max(sp.stats.settleMs, sp.response)) + " ms"
        }
    }
    MotionText {
        objectName: "spring-stats:" + sp.key
        width: graph.width
        small: true
        text: I18n.fmt("motion.ui.spring.summary", { over: (sp.stats.overshoot * 100).toFixed(1), settle: sp.stats.settleMs })
    }
}
