import QtQuick
import Quickshell
import "../core"
import "island"

// Quick settings in the bar (K24): one glyph in a square as thick as the bar, so the pointer target is the
// bar's full thickness, as for a tray icon (the theme never makes the bar thinner than 32 px). Presentational:
// it reports a click and the Bar sends quick.toggle. `open` is the quick panel's state (runtime.ui.panel),
// shown as a pressed toggle in the primary button's colours (Theme roles, as Button).
Item {
    id: q
    property bool open: false
    signal clicked()
    // K61 (docs/ux/texture.md "Controls"): the relief lies over the square and the glyph while the square is filled (open,
    // pressed or hovered), in a window that shares its sheet (Relief makes its own otherwise: a pair per control). A
    // transparent square gets none: over the bar's own relief it would double the shading and show as a square.
    readonly property var qsw: Window.window ? QsWindow.window : null
    readonly property bool sheeted: !!(qsw && qsw.tileSheet)
    readonly property bool filled: q.open || ma.pressed || hover.hovered
    readonly property bool ownRelief: Theme.texControls && sheeted && filled
    // At rest the square is transparent: the glyph alone carries the relief, masked by its own alpha (row 285), so the bar's
    // ground around it does not halo.
    readonly property bool glyphRelief: Theme.texControls && sheeted && !filled

    width: Theme.barH
    height: Theme.barH
    activeFocusOnTab: true
    Keys.onReturnPressed: q.clicked()
    Keys.onEnterPressed: q.clicked()
    Keys.onSpacePressed: q.clicked()
    Accessible.role: Accessible.Button
    Accessible.name: I18n.tr("frontend.quick.open")
    Accessible.checkable: true
    Accessible.checked: q.open

    HoverHandler { id: hover }
    // W34: the quick panel grows out of this button (a top or bottom bar's; IslandGeom's origins).
    AnchorReport { target: q; key: "quick"; output: q.qsw && q.qsw.screen ? q.qsw.screen.name : ""; enabled: q.qsw ? q.qsw.vertical !== true : false }
    // The drawn square sits 3 px in from the target on each side, as the tray icons' hover square does.
    Rectangle {
        anchors.centerIn: parent
        width: parent.width - 6
        height: parent.height - 6
        radius: Theme.rSm
        // The same theme roles as Button (primary when open), no colour of its own (rule 4).
        color: q.open ? Theme.accent : (ma.pressed || hover.hovered ? Theme.containerHigh : "transparent")
        opacity: q.open && (ma.pressed || hover.hovered) ? 0.85 : 1
        // The colour eases over the quick motion; the animation runs only while the bar is shown (Ma).
        Behavior on color {
            enabled: q.visible
            ColorAnimation { duration: Theme.quickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve }
        }
    }
    Text {
        id: glyph
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        anchors.centerIn: parent
        color: q.open ? Theme.fgOnAccent : Theme.fg
        font.pixelSize: Theme.fs + 2
        font.family: Theme.fam(text, Theme.families)
        text: "◐"
    }
    // The relief over the square and the glyph, under the focus ring (the square's own size, 3 px in).
    Loader {
        active: q.ownRelief
        anchors.centerIn: parent
        width: parent.width - 6
        height: parent.height - 6
        sourceComponent: Relief { anchors.fill: parent; radius: Theme.rSm }
    }
    // The glyph's relief at rest: a parked, non-live copy of the glyph is the mask (row 285), refreshed when its shape changes.
    Loader {
        active: q.glyphRelief && glyph.visible
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
                readonly property var key: [glyph.text, glyph.font.pixelSize, glyph.font.family, glyph.width, glyph.height]
                onKeyChanged: scheduleUpdate()
                Component.onCompleted: scheduleUpdate()
            }
            Relief { anchors.fill: parent; radius: 0; mask: glyphMask }
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        onClicked: q.clicked()
    }
    FocusRing {
        anchors.centerIn: parent
        width: parent.width - 6
        height: parent.height - 6
        shown: q.activeFocus
        corner: Theme.rSm
        stroke: q.open ? Theme.fgOnAccent : Theme.focusRing
    }
}
