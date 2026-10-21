import QtQuick
import Quickshell
import "../core"

// A sidebar's button at the bar's end (I154, `sidebar.bar_buttons`; ii opens its sidebars from the bar's two ends, Windows
// 11 from the taskbar's corners): a panel glyph in a square as thick as the bar, as the quick button. Presentational: it
// reports a click and the Bar sends `sidebar.toggle`; `open` is `runtime.ui.sidebar` for this side on this output, shown
// as a pressed toggle in the primary button's colours (Theme roles only, rule 4).
Item {
    id: sb
    property string side: "right"
    property bool open: false
    signal clicked()

    width: Theme.barH
    height: Theme.barH
    objectName: "sidebar-button:" + sb.side
    activeFocusOnTab: true
    Keys.onReturnPressed: sb.clicked()
    Keys.onEnterPressed: sb.clicked()
    Keys.onSpacePressed: sb.clicked()
    Accessible.role: Accessible.Button
    Accessible.name: I18n.tr("sidebar.bar." + sb.side)
    Accessible.checkable: true
    Accessible.checked: sb.open

    // Test only (KURASHI_BAR_GEOMETRY=1, frontend/test-sidebar-panel.sh): its box in the bar's window once laid out.
    Timer {
        running: sb.visible && Quickshell.env("KURASHI_BAR_GEOMETRY") === "1"
        interval: 500
        onTriggered: {
            var a = sb.mapToItem(null, 0, 0)
            console.log("SIDEBARBTN " + sb.side + " " + [a.x, a.y, a.x + sb.width, a.y + sb.height].map(Math.round).join(" "))
        }
    }
    HoverHandler { id: hover }
    Rectangle {
        anchors.centerIn: parent
        width: parent.width - 6
        height: parent.height - 6
        radius: Theme.rSm
        color: sb.open ? Theme.accent : (ma.pressed || hover.hovered ? Theme.containerHigh : "transparent")
        opacity: sb.open && (ma.pressed || hover.hovered) ? 0.85 : 1
        Behavior on color {
            enabled: sb.visible
            ColorAnimation { duration: Theme.quickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve }
        }
    }
    Icon {
        anchors.centerIn: parent
        name: sb.side === "left" ? "left_panel_open" : "right_panel_open"
        glyph: sb.side === "left" ? "◧" : "◨"
        color: sb.open ? Theme.fgOnAccent : Theme.fg
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        onClicked: sb.clicked()
    }
    FocusRing {
        anchors.centerIn: parent
        width: parent.width - 6
        height: parent.height - 6
        shown: sb.activeFocus
        corner: Theme.rSm
        stroke: sb.open ? Theme.fgOnAccent : Theme.focusRing
    }
}
