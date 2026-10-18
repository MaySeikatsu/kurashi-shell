pragma ComponentBehavior: Bound
import QtQuick
import "format.js" as F

// The bar widget (docs/ux/sysmon.md "Design"): the stats Settings chose, "CPU 12 % · RAM 41 %", with tabular
// digits and a width per value that its widest figure needs, so a changing number never moves its neighbours.
// The daemon's level picks the glyph and the tint (never colour alone, never blinking). Click opens the panel;
// middle click cycles what the bar shows (all the chosen stats, then each alone); right click opens the panel
// on its action menu (Pause, Settings, Open in btop). The peek's facts (the ones behind the figures) are the
// accessible description for now; a visible peek waits for the Stage-hosted peek (K19 rules out a popup surface
// per widget; BACKLOG B9/I47). It watches the summary only while it is placed, and the process list only while
// the widget has keyboard focus (Ma).
Item {
    id: widget
    required property var store
    required property var theme
    required property var i18n

    readonly property var s: store.docs["mod.sysmon"]
    readonly property var procs: store.docs["mod.sysmon.procs"]
    readonly property bool loaded: s !== undefined && s.loading !== true
    readonly property var stats: loaded && s.bar !== undefined ? s.bar : []
    // Middle click: 0 shows every chosen stat, n shows only the n-th one.
    property int view: 0
    readonly property var shown: view >= 1 && view <= stats.length ? [stats[view - 1]] : stats
    readonly property bool paused: loaded && s.paused === true
    readonly property string level: worstLevel()
    readonly property string glyph: paused ? "‖ " : (level === "critical" ? "■ " : (level === "activity" ? "▲ " : ""))
    readonly property string caption: textOf()
    readonly property string sparkStat: firstWithHistory()
    // A shown temperature with no sensor reads "–", never 0: the accessible name says why (the "no sensor" state).
    readonly property bool noSensor: loaded && s.available === true && shown.indexOf("temp") >= 0 && s.temp === undefined
    // The activity tint: the theme's warn role when the theme has one, else the accent; critical is the error role.
    readonly property color activityInk: theme.tokens["color.status.warn"] !== undefined
        ? theme.tokens["color.status.warn"] : theme.accent

    function tr(key) {
        return widget.i18n.tr(key)
    }

    function labelOf(stat) {
        return tr("sysmon.bar." + stat)
    }

    function valueOf(stat) {
        if (!loaded) return tr("sysmon.bar.wait")
        if (!s.available) return tr("sysmon.bar.none")
        if (stat === "cpu") return s.cpu.pct !== undefined ? F.pct(s.cpu.pct) : tr("sysmon.bar.wait")
        if (stat === "mem") return s.mem !== undefined ? F.pct(s.mem.pct) : "–"
        if (stat === "temp") return s.temp !== undefined ? F.temp(s.temp.c) : "–"
        if (stat === "load") return F.load(s.load1)
        return ""
    }

    // Every value gets the width of the widest figure its stat can show (the probes below).
    function widthOf(stat) {
        if (stat === "temp") return probeTemp.implicitWidth
        if (stat === "load") return probeLoad.implicitWidth
        return probePct.implicitWidth
    }

    function levelOf(stat) {
        if (!loaded) return "normal"
        if (stat === "cpu" && s.cpu.level !== undefined) return s.cpu.level
        if (stat === "mem" && s.mem !== undefined && s.mem.level !== undefined) return s.mem.level
        if (stat === "temp" && s.temp !== undefined && s.temp.level !== undefined) return s.temp.level
        return "normal"
    }

    // The worst level of the stats shown: critical beats activity beats normal.
    function worstLevel() {
        var worst = "normal"
        for (var i = 0; i < shown.length; i++) {
            var l = levelOf(shown[i])
            if (l === "critical") return "critical"
            if (l === "activity") worst = "activity"
        }
        return worst
    }

    function textOf() {
        if (!loaded) return tr("sysmon.bar.wait")
        var parts = []
        for (var i = 0; i < shown.length; i++) parts.push(labelOf(shown[i]) + " " + valueOf(shown[i]))
        return parts.join(" · ")
    }

    // The first shown stat that keeps a history (load does not): its last 30 samples are the bar's sparkline.
    function firstWithHistory() {
        for (var i = 0; i < shown.length; i++) {
            if (shown[i] === "cpu" || shown[i] === "mem" || shown[i] === "temp") return shown[i]
        }
        return ""
    }

    function historyOf(stat) {
        if (!loaded || stat === "") return []
        var src = stat === "cpu" ? s.cpu : (stat === "mem" ? s.mem : s.temp)
        if (src === undefined || src.history === undefined) return []
        return src.history.slice(-30)
    }

    // The peek's lines: the state first when the figures are not live, then the cores (highest and average), the load,
    // the memory pressure and the process that uses the most CPU (from the process document, read while the peek shows).
    function peekFacts() {
        var out = []
        if (!loaded) return out
        if (paused) out.push(tr("sysmon.panel.paused"))
        if (!s.available) return out
        var per = s.cpu.per_core
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

    // The peek's facts are read while the widget has keyboard focus (they are its accessible description). It stays
    // for a moment after focus leaves, so a quick round trip does not resubscribe.
    readonly property bool peekWanted: widget.activeFocus
    readonly property var peekLines: peekFacts()
    property bool peekOpen: false
    onPeekWantedChanged: {
        if (peekWanted) {
            peekHide.stop()
            peekOpen = true
        } else {
            peekHide.restart()
        }
    }
    Timer {
        id: peekHide
        interval: 250
        onTriggered: widget.peekOpen = false
    }
    // The process list is read only while the peek shows (Ma).
    onPeekOpenChanged: {
        if (peekOpen) widget.store.watch("mod.sysmon.procs")
        else widget.store.unwatch("mod.sysmon.procs")
    }

    // Keeps the summary subscribed while the widget is placed; released when it is removed.
    Component.onCompleted: widget.store.watch("mod.sysmon")
    Component.onDestruction: {
        widget.store.unwatch("mod.sysmon")
        if (widget.peekOpen) widget.store.unwatch("mod.sysmon.procs")
    }

    // Probes for the widths: hidden texts in the value font (tabular figures), measured by the layout.
    Text {
        id: probePct
        visible: false
        text: "100 %"
        font.pixelSize: widget.theme.fsLabel
        font.family: widget.theme.fam(text, widget.theme.families)
        font.features: ({"tnum": 1})
    }
    Text {
        id: probeTemp
        visible: false
        text: "100 °C"
        font.pixelSize: widget.theme.fsLabel
        font.family: widget.theme.fam(text, widget.theme.families)
        font.features: ({"tnum": 1})
    }
    Text {
        id: probeLoad
        visible: false
        text: "10.00"
        font.pixelSize: widget.theme.fsLabel
        font.family: widget.theme.fam(text, widget.theme.families)
        font.features: ({"tnum": 1})
    }

    implicitWidth: row.implicitWidth + widget.theme.gap * 2
    implicitHeight: widget.theme.barH
    // Paused: the figures are from before the pause, dimmed as the panel dims them.
    opacity: widget.paused ? widget.theme.staleOpacity : 1

    // The keyboard focus ring, drawn inside the widget so it shows on every surface.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: widget.theme.rSm
        color: "transparent"
        border.width: widget.activeFocus ? 1 : 0
        border.color: widget.theme.focusRing
    }

    // Children of the Row take no anchors (the Row positions them); the sparkline's box is the one anchored child.
    Row {
        id: row
        anchors.centerIn: parent
        spacing: widget.theme.gap

        Text {
            visible: widget.glyph !== ""
            text: widget.glyph
            color: widget.level === "critical" ? widget.theme.error : widget.activityInk
            font.pixelSize: widget.theme.fsLabel
            font.family: widget.theme.fam(text, widget.theme.families)
        }
        Repeater {
            model: widget.shown
            delegate: Row {
                id: cell
                required property var modelData
                required property int index
                spacing: widget.theme.xs

                Text {
                    visible: cell.index > 0
                    text: "·"
                    color: widget.theme.dim
                    font.pixelSize: widget.theme.fsLabel
                    font.family: widget.theme.fam(text, widget.theme.families)
                }
                Text {
                    text: widget.labelOf(cell.modelData)
                    color: widget.theme.dim
                    font.pixelSize: widget.theme.fsLabel
                    font.family: widget.theme.fam(text, widget.theme.families)
                }
                Text {
                    width: widget.widthOf(cell.modelData)
                    horizontalAlignment: Text.AlignRight
                    text: widget.valueOf(cell.modelData)
                    color: widget.levelOf(cell.modelData) === "critical" ? widget.theme.error
                        : (widget.levelOf(cell.modelData) === "activity" ? widget.activityInk : widget.theme.fg)
                    font.pixelSize: widget.theme.fsLabel
                    font.family: widget.theme.fam(text, widget.theme.families)
                    font.features: ({"tnum": 1})
                }
            }
        }
        // The optional sparkline (bar_spark): 30 samples of the first shown stat, in a box as tall as the bar's text.
        Item {
            visible: widget.s !== undefined && widget.s.bar_spark === true && widget.sparkStat !== ""
            width: visible ? 36 : 0
            height: widget.theme.barH

            Spark {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                width: parent.width
                height: Math.round(widget.theme.barH * 0.5)
                theme: widget.theme
                values: widget.historyOf(widget.sparkStat)
                capacity: 30
                ceiling: 100
                stroke: widget.theme.dim
                description: widget.sparkStat !== "" ? F.fill(widget.tr("sysmon.panel.history"),
                    {what: widget.labelOf(widget.sparkStat), n: 30}) : ""
            }
        }
    }

    // Left: the panel. Right: the panel on its menu. Middle: the next view of the stats. Each click that opens the
    // panel sets the menu flag it wants, so an earlier click's flag never opens the wrong view.
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                widget.view = (widget.view + 1) % (widget.stats.length + 1)
                return
            }
            widget.store.act("sysmon.menu", {on: mouse.button === Qt.RightButton})
            widget.store.act("mod.panel.open", {id: "sysmon", panel: "sysmon"})
        }
    }
    activeFocusOnTab: true
    Keys.onReturnPressed: {
        widget.store.act("sysmon.menu", {on: false})
        widget.store.act("mod.panel.open", {id: "sysmon", panel: "sysmon"})
    }
    Keys.onSpacePressed: {
        widget.store.act("sysmon.menu", {on: false})
        widget.store.act("mod.panel.open", {id: "sysmon", panel: "sysmon"})
    }
    Accessible.role: Accessible.Button
    Accessible.name: tr("sysmon.bar.open") + ": " + caption
        + (paused ? ", " + tr("sysmon.panel.paused") : "")
        + (noSensor ? ", " + tr("sysmon.bar.no_sensor") : "")
        + (level === "normal" ? "" : ", " + tr("sysmon.state." + level))
    Accessible.description: peekLines.join(" · ")
}
