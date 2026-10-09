import QtQuick
import "../core"

// Quick settings in the bar (K24): one glyph in a square as thick as the bar, so the pointer target is the
// bar's full thickness, as for a tray icon (the theme never makes the bar thinner than 32 px). Presentational:
// it reports a click and the Bar sends quick.toggle. `open` is the quick panel's state (runtime.ui.panel),
// shown as a pressed toggle in the primary button's colours (Theme roles, as Button).
Item {
    id: q
    property bool open: false
    signal clicked()

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
        anchors.centerIn: parent
        color: q.open ? Theme.fgOnAccent : Theme.fg
        font.pixelSize: Theme.fs + 2
        font.family: Theme.fam(text, Theme.families)
        text: "◐"
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
