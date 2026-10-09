import QtQuick
import "format.js" as F

// The bar widget (docs/ux/sysmon.md "Design"): the stats Settings chose, "CPU 12 % · RAM 41 %", in figures of
// fixed width. The daemon's level decides the glyph and the colour (never colour alone); a click opens the panel.
// It watches the summary only while it is placed (Ma).
Item {
    id: widget
    required property var store
    required property var theme
    required property var i18n

    readonly property var s: store.docs["mod.sysmon"]
    readonly property bool loaded: s !== undefined && s.loading !== true
    readonly property var stats: loaded && s.bar !== undefined ? s.bar : []
    readonly property string level: worstLevel()
    readonly property string glyph: level === "critical" ? "■ " : (level === "activity" ? "▲ " : "")
    readonly property string caption: textOf()

    function tr(key) {
        return widget.i18n.tr(key)
    }

    // The worst level among the shown stats: critical beats activity beats normal.
    function worstLevel() {
        if (!loaded) return "normal"
        var levels = []
        if (s.cpu !== undefined) levels.push(s.cpu.level)
        if (s.mem !== undefined) levels.push(s.mem.level)
        if (s.temp !== undefined) levels.push(s.temp.level)
        if (levels.indexOf("critical") >= 0) return "critical"
        if (levels.indexOf("activity") >= 0) return "activity"
        return "normal"
    }

    function part(stat) {
        if (stat === "cpu") {
            return tr("sysmon.bar.cpu") + " " + (s.cpu.pct !== undefined ? F.pct(s.cpu.pct) : tr("sysmon.bar.wait"))
        }
        if (stat === "mem") {
            return tr("sysmon.bar.mem") + " " + (s.mem !== undefined ? F.pct(s.mem.pct) : tr("sysmon.bar.none"))
        }
        if (stat === "temp") {
            return tr("sysmon.bar.temp") + " " + (s.temp !== undefined ? F.temp(s.temp.c) : tr("sysmon.bar.none"))
        }
        if (stat === "load") {
            return tr("sysmon.bar.load") + " " + F.load(s.load1)
        }
        return ""
    }

    function textOf() {
        if (!loaded) return tr("sysmon.bar.wait")
        if (!s.available) return tr("sysmon.bar.none")
        var parts = []
        for (var i = 0; i < stats.length; i++) parts.push(part(stats[i]))
        return parts.join(" · ")
    }

    implicitWidth: label.implicitWidth + widget.theme.gap * 2
    implicitHeight: widget.theme.barH
    // Paused: the figures are from before the pause, shown dimmed as the panel shows them.
    opacity: widget.s !== undefined && widget.s.paused === true ? widget.theme.staleOpacity : 1

    Text {
        id: label
        anchors.centerIn: parent
        text: widget.glyph + widget.caption
        color: widget.level === "critical" ? widget.theme.error : widget.theme.fg
        font.pixelSize: widget.theme.fsLabel
        font.family: widget.theme.fam(text, widget.theme.families)
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: widget.store.act("mod.panel.open", {id: "sysmon", panel: "sysmon"})
    }
    Accessible.role: Accessible.Button
    Accessible.name: tr("sysmon.bar.open") + ": " + caption
}
