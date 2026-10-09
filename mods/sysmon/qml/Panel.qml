pragma ComponentBehavior: Bound
import QtQuick
import "format.js" as F

// The system monitor panel (`panel:sysmon`, docs/ux/sysmon.md "Panel"): tiles with 60-sample sparklines and the
// source of each number, the cores, disk and network throughput, pressure, the top processes with End and
// Force quit, and a footer that says how often it samples. It subscribes only while it is open (Ma), and
// every number and level is the daemon's; this file only lays them out.
Item {
    id: panel
    required property var store
    required property var theme
    required property var i18n

    readonly property var s: store.docs["mod.sysmon"]
    readonly property var procs: store.docs["mod.sysmon.procs"]
    readonly property bool loading: s === undefined || s.loading === true
    readonly property bool unavailable: !loading && s.available !== true
    readonly property bool paused: s !== undefined && s.paused === true
    readonly property var cpu: s !== undefined && s.cpu !== undefined ? s.cpu : ({})
    readonly property var mem: s !== undefined ? s.mem : undefined
    readonly property var temp: s !== undefined ? s.temp : undefined
    readonly property var cores: cpu.per_core !== undefined ? cpu.per_core : []
    readonly property var gpus: s !== undefined && s.gpus !== undefined ? s.gpus : []
    readonly property var gpu: primaryGpu()
    property bool coresOpen: false

    function tr(key) {
        return i18n.tr(key)
    }

    // The GPU the tile shows: the first awake one, else the first listed. The others get a line each.
    function primaryGpu() {
        for (var i = 0; i < gpus.length; i++) {
            if (gpus[i].state === "awake") return gpus[i]
        }
        return gpus.length > 0 ? gpus[0] : undefined
    }

    function otherGpus() {
        var out = []
        for (var i = 0; i < gpus.length; i++) {
            if (gpus[i] !== gpu) out.push(gpus[i])
        }
        return out
    }

    function gpuValue(g) {
        if (g === undefined || g.state !== "awake" || g.util === undefined) return "–"
        return F.pct(g.util)
    }

    function gpuDetail(g) {
        if (g === undefined) return ""
        if (g.state !== "awake") return g.id + " · " + tr("sysmon.panel.gpu_asleep")
        var parts = [g.vendor !== undefined ? g.vendor : g.id]
        if (g.vram !== undefined) parts.push(F.bytes(g.vram.used) + " / " + F.bytes(g.vram.total))
        if (g.util === undefined) parts.push(tr("sysmon.panel.gpu_no_util"))
        if (g.temp_c !== undefined) parts.push(F.temp(g.temp_c))
        return parts.join(" · ")
    }

    function historyOf(v) {
        return v !== undefined && v.history !== undefined ? v.history : []
    }

    function describe(label, values) {
        return F.fill(tr("sysmon.panel.history"), {what: label, n: values.length})
    }

    // "Pressure: memory some 12 % · full 3 %" for each resource the kernel reports.
    function psi(label, p) {
        var text = tr(label) + " " + F.fill(tr("sysmon.panel.pressure.some"), {v: p.some})
        if (p.full !== undefined) text += " · " + F.fill(tr("sysmon.panel.pressure.full"), {v: p.full})
        return text
    }

    function rwText() {
        if (s === undefined || s.disk === undefined) return ""
        return F.fill(tr("sysmon.panel.rw"), {r: F.rate(s.disk.read_bps), w: F.rate(s.disk.write_bps)})
    }

    function netText() {
        if (s === undefined || s.net === undefined) return ""
        return F.fill(tr("sysmon.panel.rxtx"), {r: F.rate(s.net.rx_bps), w: F.rate(s.net.tx_bps)})
    }

    implicitWidth: 440
    implicitHeight: column.implicitHeight

    Component.onCompleted: {
        store.watch("mod.sysmon")
        store.watch("mod.sysmon.procs")
    }
    Component.onDestruction: {
        store.unwatch("mod.sysmon")
        store.unwatch("mod.sysmon.procs")
    }

    Column {
        id: column
        width: panel.width
        spacing: panel.theme.pad

        // Title, and the pause control on the right.
        Item {
            width: parent.width
            height: heading.implicitHeight
            Text {
                id: heading
                text: panel.tr("sysmon.panel.title")
                color: panel.theme.fg
                font.pixelSize: panel.theme.fsTitle
                font.family: panel.theme.fam(text, panel.theme.families)
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            PillButton {
                theme: panel.theme
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: panel.paused ? panel.tr("sysmon.panel.resume") : panel.tr("sysmon.panel.pause")
                active: panel.paused
                available: panel.s !== undefined
                onActivated: panel.store.act("sysmon.pause", {paused: !panel.paused})
            }
        }

        // The state, when there is no value to show or the values are from before a pause.
        Text {
            visible: text !== ""
            width: parent.width
            text: panel.loading ? panel.tr("sysmon.panel.loading")
                : (panel.unavailable ? panel.tr("sysmon.panel.unavailable")
                : (panel.paused ? panel.tr("sysmon.panel.stale") : ""))
            color: panel.theme.dim
            wrapMode: Text.WordWrap
            font.pixelSize: panel.theme.fsCaption
            font.family: panel.theme.fam(text, panel.theme.families)
        }

        // Paused: every value is from before the pause, so the body is dimmed as one (docs/ux/sysmon.md "States").
        Grid {
            columns: 2
            spacing: panel.theme.gap
            opacity: panel.paused ? panel.theme.staleOpacity : 1
            visible: !panel.loading && !panel.unavailable

            Tile {
                theme: panel.theme
                label: panel.tr("sysmon.panel.cpu")
                value: panel.cpu.pct !== undefined ? F.pct(panel.cpu.pct) : "…"
                detail: panel.s !== undefined && panel.s.load1 !== undefined
                    ? panel.tr("sysmon.panel.load") + " " + F.load(panel.s.load1) : ""
                history: panel.historyOf(panel.cpu)
                level: panel.cpu.level !== undefined ? panel.cpu.level : "normal"
                sparkDescription: panel.describe(panel.tr("sysmon.panel.cpu"), panel.historyOf(panel.cpu))
            }
            Tile {
                theme: panel.theme
                label: panel.tr("sysmon.panel.mem")
                value: panel.mem !== undefined ? F.pct(panel.mem.pct) : "–"
                detail: panel.mem !== undefined
                    ? F.bytes(panel.mem.used) + " / " + F.bytes(panel.mem.total)
                        + (panel.mem.swap !== undefined
                            ? " · " + panel.tr("sysmon.panel.swap") + " " + F.bytes(panel.mem.swap.used) : "")
                    : ""
                history: panel.historyOf(panel.mem)
                level: panel.mem !== undefined && panel.mem.level !== undefined ? panel.mem.level : "normal"
                sparkDescription: panel.describe(panel.tr("sysmon.panel.mem"), panel.historyOf(panel.mem))
            }
            Tile {
                theme: panel.theme
                label: panel.tr("sysmon.panel.temp")
                value: panel.temp !== undefined ? F.temp(panel.temp.c) : "–"
                detail: panel.temp !== undefined ? panel.temp.source : panel.tr("sysmon.panel.no_sensor")
                history: panel.historyOf(panel.temp)
                ceiling: 100
                level: panel.temp !== undefined && panel.temp.level !== undefined ? panel.temp.level : "normal"
                sparkDescription: panel.describe(panel.tr("sysmon.panel.temp"), panel.historyOf(panel.temp))
            }
            Tile {
                theme: panel.theme
                visible: panel.gpu !== undefined
                label: panel.tr("sysmon.panel.gpu")
                value: panel.gpuValue(panel.gpu)
                detail: panel.gpuDetail(panel.gpu)
                sparkDescription: panel.describe(panel.tr("sysmon.panel.gpu"), [])
            }
        }

        // The GPUs the tile does not show, one line each.
        Repeater {
            model: panel.otherGpus()
            delegate: Text {
                required property var modelData
                width: panel.width
                text: panel.tr("sysmon.panel.gpu") + " · " + panel.gpuDetail(modelData)
                color: panel.theme.dim
                wrapMode: Text.WordWrap
                font.pixelSize: panel.theme.fsCaption
                font.family: panel.theme.fam(text, panel.theme.families)
            }
        }

        // Cores: a bar per core, collapsed by default. Above 16 cores the bars would be noise: the average stands.
        Column {
            visible: !panel.loading && !panel.unavailable && panel.cores.length > 0
            width: parent.width
            spacing: panel.theme.xs

            PillButton {
                theme: panel.theme
                label: panel.coresOpen ? panel.tr("sysmon.panel.cores_hide") : panel.tr("sysmon.panel.cores_show")
                onActivated: panel.coresOpen = !panel.coresOpen
            }
            Row {
                id: coreBars
                visible: panel.coresOpen && panel.cores.length <= 16
                width: parent.width
                height: 40
                spacing: 2

                Repeater {
                    model: panel.cores
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: (coreBars.width - 2 * (panel.cores.length - 1)) / panel.cores.length
                        height: coreBars.height
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: Math.max(2, parent.height * parent.modelData / 100)
                            radius: 2
                            color: panel.theme.dim
                        }
                        Accessible.role: Accessible.Graphic
                        Accessible.name: "CPU " + (index + 1) + ": " + F.pct(modelData)
                    }
                }
            }
            Text {
                visible: panel.coresOpen && panel.cores.length > 16
                width: parent.width
                text: F.fill(panel.tr("sysmon.panel.cores_avg"), {n: panel.cores.length})
                color: panel.theme.dim
                font.pixelSize: panel.theme.fsCaption
                font.family: panel.theme.fam(text, panel.theme.families)
            }
        }

        // Throughput, pressure and swap: each line only where the machine reports the figure.
        Column {
            visible: !panel.loading && !panel.unavailable
            width: parent.width
            spacing: panel.theme.xs
            opacity: panel.paused ? panel.theme.staleOpacity : 1

            Text {
                visible: panel.s !== undefined && panel.s.disk !== undefined
                width: parent.width
                text: panel.tr("sysmon.panel.disk") + ": " + panel.rwText()
                color: panel.theme.fg
                font.pixelSize: panel.theme.fsLabel
                font.family: panel.theme.fam(text, panel.theme.families)
            }
            Text {
                visible: panel.s !== undefined && panel.s.net !== undefined
                width: parent.width
                text: panel.tr("sysmon.panel.net") + ": " + panel.netText()
                color: panel.theme.fg
                font.pixelSize: panel.theme.fsLabel
                font.family: panel.theme.fam(text, panel.theme.families)
            }
            Text {
                visible: panel.s !== undefined && panel.s.pressure !== undefined && panel.s.pressure.memory !== undefined
                width: parent.width
                text: panel.tr("sysmon.panel.pressure") + ": " + (visible ? panel.psi("sysmon.panel.mem", panel.s.pressure.memory) : "")
                color: panel.theme.fg
                wrapMode: Text.WordWrap
                font.pixelSize: panel.theme.fsLabel
                font.family: panel.theme.fam(text, panel.theme.families)
            }
            Text {
                visible: panel.s !== undefined && panel.s.pressure !== undefined && panel.s.pressure.cpu !== undefined
                width: parent.width
                text: visible ? panel.psi("sysmon.panel.cpu", panel.s.pressure.cpu) : ""
                color: panel.theme.dim
                font.pixelSize: panel.theme.fsCaption
                font.family: panel.theme.fam(text, panel.theme.families)
            }
            Text {
                visible: panel.mem !== undefined && panel.mem.zram !== undefined
                width: parent.width
                text: visible ? F.fill(panel.tr("sysmon.panel.zram"), {r: panel.mem.zram.ratio.toFixed(1)}) : ""
                color: panel.theme.dim
                font.pixelSize: panel.theme.fsCaption
                font.family: panel.theme.fam(text, panel.theme.families)
            }
        }

        // The top processes: the sort, then the list with End and Force quit.
        Column {
            visible: !panel.loading && !panel.unavailable
            width: parent.width
            spacing: panel.theme.gap
            opacity: panel.paused ? panel.theme.staleOpacity : 1

            Row {
                width: parent.width
                spacing: panel.theme.gap
                Text {
                    text: panel.tr("sysmon.panel.procs")
                    color: panel.theme.fg
                    font.pixelSize: panel.theme.fsLabel
                    font.family: panel.theme.fam(text, panel.theme.families)
                    anchors.verticalCenter: parent.verticalCenter
                }
                PillButton {
                    theme: panel.theme
                    label: panel.tr("sysmon.panel.sort_cpu")
                    active: panel.procs !== undefined && panel.procs.sort === "cpu"
                    onActivated: panel.store.act("sysmon.sort", {by: "cpu"})
                }
                PillButton {
                    theme: panel.theme
                    label: panel.tr("sysmon.panel.sort_mem")
                    active: panel.procs !== undefined && panel.procs.sort === "mem"
                    onActivated: panel.store.act("sysmon.sort", {by: "mem"})
                }
            }
            ProcessList {
                width: parent.width
                store: panel.store
                theme: panel.theme
                i18n: panel.i18n
                doc: panel.procs
            }
        }

        // The footer: how often it samples, and whether the trouble is watched while nothing is open.
        Text {
            visible: panel.s !== undefined && panel.s.interval_s !== undefined
            width: parent.width
            text: visible
                ? F.fill(panel.tr("sysmon.panel.footer"), {s: panel.s.interval_s})
                    + (panel.s.watching === true ? " · " + panel.tr("sysmon.panel.watching") : "")
                : ""
            color: panel.theme.dim
            font.pixelSize: panel.theme.fsCaption
            font.family: panel.theme.fam(text, panel.theme.families)
        }
    }
}
