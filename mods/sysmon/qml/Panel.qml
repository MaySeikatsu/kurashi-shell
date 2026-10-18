pragma ComponentBehavior: Bound
import QtQuick
import "format.js" as F

// The system monitor panel (`panel:sysmon`, docs/ux/sysmon.md "Panel"). It asks the Stage for a 440 px card (`cardWidth`,
// the brief's "~440 px"), so its content is 408 px: two columns of tiles and one line per process (name, then the
// figures and actions). Every width below is the panel's own `width`, never a constant, so the layout follows the card (B18). The
// body is the figures, or, after a right click on the bar, the action menu (Pause, Settings, Open in btop). It
// subscribes while it is open (Ma); every number and level is the daemon's, this file only lays them out.
Item {
    id: panel
    required property var store
    required property var theme
    required property var i18n

    readonly property var s: store.docs["mod.sysmon"]
    readonly property var procs: store.docs["mod.sysmon.procs"]
    readonly property bool paused: s !== undefined && s.paused === true
    // "settings" (only Settings resumes it) or "panel" (the Pause control): the view says which.
    readonly property string pausedBy: s !== undefined && s.paused_by !== undefined ? s.paused_by : ""
    readonly property bool menuOpen: s !== undefined && s.menu === true
    readonly property bool showBody: s !== undefined && s.loading !== true && s.available === true
    readonly property var cpu: s !== undefined && s.cpu !== undefined ? s.cpu : ({})
    readonly property var mem: s !== undefined ? s.mem : undefined
    readonly property var temp: s !== undefined ? s.temp : undefined
    readonly property var battery: s !== undefined ? s.battery : undefined
    readonly property var cores: cpu.per_core !== undefined ? cpu.per_core : []
    readonly property var gpus: s !== undefined && s.gpus !== undefined ? s.gpus : []
    readonly property var gpu: primaryGpu()
    // What the panel says about its state: loading, paused, unavailable, or nothing (the figures speak).
    readonly property string status: {
        if (s === undefined || (s.loading === true && !paused)) return tr("sysmon.panel.loading")
        if (s.loading === true) return tr("sysmon.panel.paused_none")
        if (s.available !== true) return tr("sysmon.panel.unavailable")
        if (paused) return tr(pausedBy === "settings" ? "sysmon.panel.paused_settings" : "sysmon.panel.stale")
        return ""
    }
    property bool coresOpen: false
    // The last refusal or failure of a menu action, translated; empty when the last one worked.
    property string notice: ""

    function tr(key) {
        return i18n.tr(key)
    }

    // The GPU the tile shows is the one the daemon marks primary: the one that renders (I62), or the asleep one of a
    // machine with no awake GPU. The others get a line each, asleep ones included (never sampled).
    function primaryGpu() {
        for (var i = 0; i < gpus.length; i++) {
            if (gpus[i].primary === true) return gpus[i]
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

    function describe(label) {
        return F.fill(tr("sysmon.panel.history"), {what: label, n: 60})
    }

    // The host line: the figures of a container or a VM are not the machine's own.
    function hostText() {
        if (s === undefined || s.host === undefined || s.host === null) return ""
        return tr("sysmon.panel.host." + s.host)
    }

    function cpuDetail() {
        var parts = []
        if (s !== undefined && s.load1 !== undefined) parts.push(tr("sysmon.panel.load") + " " + F.load(s.load1))
        if (cpu.cores !== undefined) parts.push(F.fill(tr("sysmon.panel.cores_n"), {n: cpu.cores}))
        return parts.join(" · ")
    }

    function memDetail() {
        if (mem === undefined) return ""
        var text = F.bytes(mem.used) + " / " + F.bytes(mem.total)
        if (mem.swap !== undefined) text += " · " + tr("sysmon.panel.swap") + " " + F.bytes(mem.swap.used)
        return text
    }

    // The sensor's name and what the number is judged by. A control value says so: it runs warm on some Ryzen parts.
    function tempDetail() {
        if (temp === undefined) {
            if (s === undefined || s.temp_search === undefined) return tr("sysmon.panel.no_sensor")
            var wanted = s.temp_search.wanted.join(", ")
            var found = s.temp_search.found
            var searched = found.length === 0
                ? F.fill(tr("sysmon.panel.searched.none"), {wanted: wanted})
                : F.fill(tr("sysmon.panel.searched"), {wanted: wanted, found: found.join(", ")})
            return tr("sysmon.panel.no_sensor") + "\n" + searched
        }
        var lines = [temp.source]
        if (temp.of !== undefined) lines.push(F.fill(tr("sysmon.panel.temp.of"), {n: temp.of}))
        if (temp.levels !== undefined && temp.levels.critical !== null && temp.levels.critical !== undefined) {
            lines.push(F.fill(tr("sysmon.panel.temp.critical_from"), {c: temp.levels.critical}))
        }
        if (temp.kind === "control") lines.push(tr("sysmon.panel.temp.control"))
        return lines.join("\n")
    }

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

    function batteryLine() {
        var parts = [tr("sysmon.panel.battery")]
        if (battery.percent !== undefined) parts.push(F.pct(battery.percent))
        parts.push(tr("sysmon.battery.state." + battery.state))
        if (battery.watts !== undefined) parts.push(F.watts(battery.watts))
        return parts.join(" · ")
    }

    function batteryLeft() {
        if (battery === undefined || battery.minutes_left === undefined) return ""
        var m = battery.minutes_left
        if (m < 60) return F.fill(tr("sysmon.battery.left.m"), {m: m})
        return F.fill(tr("sysmon.battery.left.hm"), {h: Math.floor(m / 60), m: m % 60})
    }

    // What drains the battery: the process using the most CPU, while it discharges (the procs scan is subscribed).
    function drainText() {
        if (battery === undefined || battery.state !== "discharging") return ""
        if (procs === undefined || procs.hottest === undefined || procs.hottest.cpu === undefined) return ""
        return F.fill(tr("sysmon.battery.drain"), {name: F.name(procs.hottest.name, 24), pct: F.pct(procs.hottest.cpu)})
    }

    function runMenu(action, args) {
        store.act(action, args, function (done, err) {
            notice = err ? tr(err.msg) : ""
        })
    }

    // The card's outer width this panel asks for (contract row 66; the Stage clamps it to 360..720 px). The content is
    // the card less its margins, 2 × (Theme.pad + 4), the Stage's own rule, so the panel and its card agree.
    property int cardWidth: 440
    implicitWidth: cardWidth - 2 * (panel.theme.pad + 4)
    width: implicitWidth
    implicitHeight: column.implicitHeight

    Component.onCompleted: {
        store.watch("mod.sysmon")
        store.watch("mod.sysmon.procs")
    }
    Component.onDestruction: {
        // The menu belongs to this opening: a closed panel never leaves its menu flag set for the next click.
        store.act("sysmon.menu", {on: false})
        store.unwatch("mod.sysmon")
        store.unwatch("mod.sysmon.procs")
    }

    Column {
        id: column
        width: panel.width
        // Sections are close together: the panel lists eight processes, and it must fit a 1080 px screen.
        spacing: panel.theme.gap

        // Title, and the pause control on the right (inert with its reason while Settings pauses).
        Item {
            width: parent.width
            height: heading.implicitHeight
            Text {
                id: heading
                text: panel.menuOpen ? panel.tr("sysmon.panel.menu.title") : panel.tr("sysmon.panel.title")
                color: panel.theme.fg
                font.pixelSize: panel.theme.fsTitle
                font.family: panel.theme.fam(text, panel.theme.families)
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            PillButton {
                theme: panel.theme
                visible: !panel.menuOpen
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: panel.paused ? panel.tr("sysmon.panel.resume") : panel.tr("sysmon.panel.pause")
                active: panel.paused
                available: panel.s !== undefined && panel.pausedBy !== "settings"
                reason: panel.tr("sysmon.panel.paused_settings_short")
                onActivated: panel.runMenu("sysmon.pause", {paused: !panel.paused})
            }
        }

        // The host line (a container or a VM: the figures are not this machine's own) and the state line.
        Text {
            visible: panel.hostText() !== ""
            width: parent.width
            text: panel.hostText()
            color: panel.theme.dim
            wrapMode: Text.WordWrap
            font.pixelSize: panel.theme.fsCaption
            font.family: panel.theme.fam(text, panel.theme.families)
        }
        Text {
            visible: text !== ""
            width: parent.width
            text: panel.status
            color: panel.theme.dim
            wrapMode: Text.WordWrap
            font.pixelSize: panel.theme.fsCaption
            font.family: panel.theme.fam(text, panel.theme.families)
        }

        // The action menu (the bar's right click): Pause, Settings, Open in btop, and back to the figures.
        Column {
            visible: panel.menuOpen
            width: parent.width
            spacing: panel.theme.xs

            MenuRow {
                theme: panel.theme
                label: panel.paused ? panel.tr("sysmon.panel.resume") : panel.tr("sysmon.panel.pause")
                available: panel.pausedBy !== "settings"
                reason: panel.tr("sysmon.panel.paused_settings_short")
                onActivated: panel.runMenu("sysmon.pause", {paused: !panel.paused})
            }
            MenuRow {
                theme: panel.theme
                label: panel.tr("sysmon.panel.menu.settings")
                onActivated: {
                    panel.store.act("sysmon.menu", {on: false})
                    panel.store.act("settings.open", {key: "mods.sysmon.interval"})
                    panel.store.act("ui.close")
                }
            }
            MenuRow {
                theme: panel.theme
                label: panel.tr("sysmon.panel.menu.btop")
                onActivated: panel.store.act("sysmon.open_btop", {}, function (done, err) {
                    if (err) {
                        panel.notice = panel.tr(err.msg)
                    } else {
                        panel.store.act("sysmon.menu", {on: false})
                        panel.store.act("ui.close")
                    }
                })
            }
            MenuRow {
                theme: panel.theme
                label: panel.tr("sysmon.panel.menu.back")
                onActivated: panel.store.act("sysmon.menu", {on: false})
            }
            Text {
                visible: panel.notice !== ""
                width: parent.width
                text: panel.notice
                color: panel.theme.error
                wrapMode: Text.WordWrap
                font.pixelSize: panel.theme.fsCaption
                font.family: panel.theme.fam(text, panel.theme.families)
            }
        }

        // The tiles: value, 60 samples, and where the number comes from. Two columns of 160 px.
        Grid {
            id: tiles
            visible: panel.showBody && !panel.menuOpen
            width: panel.width
            columns: 2
            spacing: panel.theme.gap
            opacity: panel.paused ? panel.theme.staleOpacity : 1

            Tile {
                theme: panel.theme
                width: (tiles.width - tiles.spacing) / 2
                label: panel.tr("sysmon.panel.cpu")
                value: panel.cpu.pct !== undefined ? F.pct(panel.cpu.pct) : "…"
                detail: panel.cpuDetail()
                history: panel.historyOf(panel.cpu)
                level: panel.cpu.level !== undefined ? panel.cpu.level : "normal"
                sparkDescription: panel.describe(panel.tr("sysmon.panel.cpu"))
            }
            Tile {
                theme: panel.theme
                width: (tiles.width - tiles.spacing) / 2
                label: panel.tr("sysmon.panel.mem")
                value: panel.mem !== undefined ? F.pct(panel.mem.pct) : "–"
                detail: panel.memDetail()
                history: panel.historyOf(panel.mem)
                level: panel.mem !== undefined && panel.mem.level !== undefined ? panel.mem.level : "normal"
                sparkDescription: panel.describe(panel.tr("sysmon.panel.mem"))
            }
            Tile {
                theme: panel.theme
                width: (tiles.width - tiles.spacing) / 2
                label: panel.tr("sysmon.panel.temp")
                value: panel.temp !== undefined ? F.temp(panel.temp.c) : "–"
                detail: panel.tempDetail()
                history: panel.historyOf(panel.temp)
                ceiling: 100
                level: panel.temp !== undefined && panel.temp.level !== undefined ? panel.temp.level : "normal"
                sparkDescription: panel.describe(panel.tr("sysmon.panel.temp"))
            }
            Tile {
                theme: panel.theme
                visible: panel.gpu !== undefined
                width: (tiles.width - tiles.spacing) / 2
                label: panel.tr("sysmon.panel.gpu")
                value: panel.gpuValue(panel.gpu)
                detail: panel.gpuDetail(panel.gpu)
                sparkDescription: panel.describe(panel.tr("sysmon.panel.gpu"))
            }
        }

        // The GPUs the tile does not show, one line each.
        Repeater {
            model: panel.showBody && !panel.menuOpen ? panel.otherGpus() : []
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
            visible: panel.showBody && !panel.menuOpen && panel.cores.length > 0
            width: panel.width
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
                        Accessible.name: panel.tr("sysmon.panel.cpu") + " " + (index + 1) + ": " + F.pct(modelData)
                    }
                }
            }
            Text {
                visible: panel.coresOpen && panel.cores.length > 16
                width: parent.width
                text: F.fill(panel.tr("sysmon.panel.cores_avg"), {n: panel.cores.length})
                color: panel.theme.dim
                wrapMode: Text.WordWrap
                font.pixelSize: panel.theme.fsCaption
                font.family: panel.theme.fam(text, panel.theme.families)
            }
        }

        // The battery: charge, state, draw and time left, and what draws the most (only where there is a battery).
        Column {
            visible: panel.showBody && !panel.menuOpen && panel.battery !== undefined
            width: parent.width
            spacing: panel.theme.xs
            opacity: panel.paused ? panel.theme.staleOpacity : 1

            Text {
                width: parent.width
                text: panel.battery !== undefined ? panel.batteryLine() : ""
                color: panel.theme.fg
                wrapMode: Text.WordWrap
                font.pixelSize: panel.theme.fsLabel
                font.family: panel.theme.fam(text, panel.theme.families)
                font.features: ({"tnum": 1})
            }
            Text {
                visible: text !== ""
                width: parent.width
                text: panel.batteryLeft()
                color: panel.theme.dim
                wrapMode: Text.WordWrap
                font.pixelSize: panel.theme.fsCaption
                font.family: panel.theme.fam(text, panel.theme.families)
            }
            Text {
                visible: text !== ""
                width: parent.width
                text: panel.drainText()
                color: panel.theme.dim
                wrapMode: Text.WordWrap
                font.pixelSize: panel.theme.fsCaption
                font.family: panel.theme.fam(text, panel.theme.families)
            }
        }

        // Throughput, pressure and zram: each line only where the machine reports the figure.
        Column {
            visible: panel.showBody && !panel.menuOpen
            width: parent.width
            spacing: panel.theme.xs
            opacity: panel.paused ? panel.theme.staleOpacity : 1

            Text {
                visible: panel.s !== undefined && panel.s.disk !== undefined
                width: parent.width
                text: panel.tr("sysmon.panel.disk") + ": " + panel.rwText()
                color: panel.theme.fg
                wrapMode: Text.WordWrap
                font.pixelSize: panel.theme.fsLabel
                font.family: panel.theme.fam(text, panel.theme.families)
            }
            Text {
                visible: panel.s !== undefined && panel.s.net !== undefined
                width: parent.width
                text: panel.tr("sysmon.panel.net") + ": " + panel.netText()
                color: panel.theme.fg
                wrapMode: Text.WordWrap
                font.pixelSize: panel.theme.fsLabel
                font.family: panel.theme.fam(text, panel.theme.families)
            }
            Text {
                visible: panel.s !== undefined && panel.s.pressure !== undefined && panel.s.pressure.memory !== undefined
                width: parent.width
                text: visible ? panel.tr("sysmon.panel.pressure") + ": " + panel.psi("sysmon.panel.mem", panel.s.pressure.memory) : ""
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
                wrapMode: Text.WordWrap
                font.pixelSize: panel.theme.fsCaption
                font.family: panel.theme.fam(text, panel.theme.families)
            }
            Text {
                visible: panel.mem !== undefined && panel.mem.zram !== undefined
                width: parent.width
                text: visible ? F.fill(panel.tr("sysmon.panel.zram"), {r: panel.mem.zram.ratio.toFixed(1)}) : ""
                color: panel.theme.dim
                wrapMode: Text.WordWrap
                font.pixelSize: panel.theme.fsCaption
                font.family: panel.theme.fam(text, panel.theme.families)
            }
        }

        // The top processes: the sort, then the list with End and Force quit.
        Column {
            visible: panel.showBody && !panel.menuOpen
            width: parent.width
            spacing: panel.theme.gap
            opacity: panel.paused ? panel.theme.staleOpacity : 1

            // The title and the two sort pills wrap rather than push past the card's edge.
            Flow {
                width: parent.width
                spacing: panel.theme.gap
                Text {
                    text: panel.tr("sysmon.panel.procs")
                    color: panel.theme.fg
                    font.pixelSize: panel.theme.fsLabel
                    font.family: panel.theme.fam(text, panel.theme.families)
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
            // What the two figures of each row are (the columns have no headers of their own).
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: panel.tr("sysmon.panel.procs_cols")
                color: panel.theme.dim
                font.pixelSize: panel.theme.fsCaption
                font.family: panel.theme.fam(text, panel.theme.families)
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
            visible: panel.showBody && !panel.menuOpen
            width: parent.width
            text: panel.showBody
                ? F.fill(panel.tr("sysmon.panel.footer"), {s: panel.s.interval_s})
                    + (panel.s.watching === true ? " · " + panel.tr("sysmon.panel.watching") : "")
                : ""
            color: panel.theme.dim
            wrapMode: Text.WordWrap
            font.pixelSize: panel.theme.fsCaption
            font.family: panel.theme.fam(text, panel.theme.families)
        }
    }
}
