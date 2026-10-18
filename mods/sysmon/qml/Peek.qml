import QtQuick
import qs.components
import "format.js" as F

// The sysmon peek (docs/ux/sysmon.md "Design"): per-core max and average, load, memory pressure and the process that uses
// the most CPU, one line each. The Stage draws it on hover or keyboard focus of the bar widget (K35). It subscribes to the
// summary and to the process list only while it shows (Ma), and it names the state first when the figures are not live.
PeekLines {
    id: peek
    // Handed in by ModLoader (K26); the core singletons are imported too.
    required property var store
    required property var theme
    required property var i18n

    Component.onCompleted: {
        peek.store.watch("mod.sysmon")
        peek.store.watch("mod.sysmon.procs")
    }
    Component.onDestruction: {
        peek.store.unwatch("mod.sysmon.procs")
        peek.store.unwatch("mod.sysmon")
    }

    readonly property var s: store.docs["mod.sysmon"]
    readonly property var procs: store.docs["mod.sysmon.procs"]
    readonly property bool loaded: s !== undefined && s.loading !== true

    function tr(key) { return peek.i18n.tr(key) }

    lines: {
        var out = []
        if (!loaded) return [tr("sysmon.bar.wait")]
        if (s.paused === true) out.push(tr("sysmon.panel.paused"))
        if (!s.available) {
            out.push(tr("sysmon.bar.none"))
            return out
        }
        var per = s.cpu !== undefined ? s.cpu.per_core : undefined
        if (per !== undefined && per.length > 0) {
            var max = 0
            var sum = 0
            for (var i = 0; i < per.length; i++) {
                max = Math.max(max, per[i])
                sum += per[i]
            }
            out.push(F.fill(tr("sysmon.bar.peek.cores"), {max: Math.round(max), avg: Math.round(sum / per.length)}))
        }
        if (s.load1 !== undefined) out.push(tr("sysmon.panel.load") + " " + F.load(s.load1))
        if (s.pressure !== undefined && s.pressure.memory !== undefined) {
            out.push(tr("sysmon.panel.pressure") + ": " + tr("sysmon.panel.mem") + " "
                + F.fill(tr("sysmon.panel.pressure.some"), {v: s.pressure.memory.some}))
        }
        if (procs !== undefined && procs.hottest !== undefined && procs.hottest !== null && procs.hottest.cpu !== undefined) {
            out.push(F.fill(tr("sysmon.bar.peek.top"), {name: F.name(procs.hottest.name, 24), pct: F.pct(procs.hottest.cpu)}))
        }
        return out
    }
}
