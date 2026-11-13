import QtQuick
import qs.core

// The drop-down's free edge, dragged for this output's height (Yakuake's handle; docs/ux/terminal.md "The places"). The
// drag previews nothing on its own: on release the height is written (`terminal.resize`, the `sizes` row of this output,
// 20–95 %) and the sheet takes it. Inert, with its reason, while the configuration forces `sizes`.
Item {
    id: g
    property bool fromTop: false
    property real screenH: 1080
    property real startPct: 0.45
    property string output: ""
    property bool forced: false
    property real dragged: 0
    Accessible.role: Accessible.Grip
    Accessible.name: forced ? I18n.tr("terminal.grip.forced") : I18n.tr("terminal.grip")
    activeFocusOnTab: !forced
    function commit(pct) {
        Store.act("terminal.resize", { output: output, height: Math.round(Math.max(20, Math.min(95, pct * 100))) })
    }
    Keys.onUpPressed: commit(startPct + (fromTop ? 0.05 : -0.05))
    Keys.onDownPressed: commit(startPct + (fromTop ? -0.05 : 0.05))
    Rectangle {
        anchors.centerIn: parent
        width: 48
        height: 4
        radius: 2
        color: Theme.fg
        opacity: hov.hovered || drag.active || g.activeFocus ? 0.55 : 0.22
    }
    HoverHandler { id: hov; cursorShape: g.forced ? Qt.ArrowCursor : Qt.SizeVerCursor }
    DragHandler {
        id: drag
        enabled: !g.forced
        target: null
        yAxis.enabled: true
        xAxis.enabled: false
        onTranslationChanged: g.dragged = translation.y
        onActiveChanged: if (!active) {
            var pct = g.startPct + (g.fromTop ? -g.dragged : g.dragged) / Math.max(1, g.screenH)
            g.dragged = 0
            g.commit(pct)
        }
    }
}
