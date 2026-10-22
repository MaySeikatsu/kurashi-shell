import QtQuick
import Quickshell
import "../core"
import "island"

// A sidebar's button at the bar's end (I154, `sidebar.bar_buttons`; ii opens its sidebars from the bar's two ends, Windows
// 11 from the taskbar's corners): a panel glyph in a square as thick as the bar, as the quick button. Presentational: it
// reports a click and the Bar sends `sidebar.toggle`; `open` is `runtime.ui.sidebar` for this side on this output, shown
// as a pressed toggle in the primary button's colours (Theme roles only, rule 4).
Item {
    id: sb
    property string side: "right"
    property bool open: false
    signal clicked()
    // K61 (docs/ux/texture.md "Controls"): the relief over the square and the glyph while the square is filled, in a window
    // that shares its sheet; a transparent square gets none (see QuickButton).
    readonly property var qsw: Window.window ? QsWindow.window : null
    readonly property bool sheeted: !!(qsw && qsw.tileSheet)
    readonly property bool filled: sb.open || ma.pressed || hover.hovered
    readonly property bool ownRelief: Theme.texControls && sheeted && filled
    // At rest the square is transparent: the glyph alone carries the relief, masked by its own alpha (row 285).
    readonly property bool glyphRelief: Theme.texControls && sheeted && !filled

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
    // W34: the sidebar grows out of this button (a top or bottom bar's; IslandGeom's origins).
    AnchorReport { target: sb; key: "sidebar:" + sb.side; output: sb.qsw && sb.qsw.screen ? sb.qsw.screen.name : ""; enabled: sb.qsw ? sb.qsw.vertical !== true : false }
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
        id: glyph
        anchors.centerIn: parent
        name: sb.side === "left" ? "left_panel_open" : "right_panel_open"
        glyph: sb.side === "left" ? "◧" : "◨"
        color: sb.open ? Theme.fgOnAccent : Theme.fg
    }
    // The relief over the square and the glyph, under the focus ring.
    Loader {
        active: sb.ownRelief
        anchors.centerIn: parent
        width: parent.width - 6
        height: parent.height - 6
        sourceComponent: Relief { anchors.fill: parent; radius: Theme.rSm }
    }
    // The glyph's relief at rest: a parked, non-live copy of the glyph is the mask (row 285), refreshed when its shape changes.
    Loader {
        active: sb.glyphRelief && glyph.visible
        x: glyph.x; y: glyph.y; width: glyph.width; height: glyph.height
        sourceComponent: Item {
            anchors.fill: parent
            ShaderEffectSource {
                id: glyphMask
                width: parent.width
                height: parent.height
                sourceItem: glyph
                live: false
                x: -100000
                y: -100000
                readonly property var key: [glyph.name, glyph.glyph, glyph.font.pixelSize, glyph.font.family, glyph.width, glyph.height]
                onKeyChanged: scheduleUpdate()
                Component.onCompleted: scheduleUpdate()
            }
            Relief { anchors.fill: parent; radius: 0; mask: glyphMask }
        }
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
