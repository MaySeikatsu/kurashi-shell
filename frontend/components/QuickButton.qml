import QtQuick
import "../core"

// Quick settings in the bar (K24): one glyph in a square as thick as the bar, so the pointer target is the
// bar's full thickness, as for a tray icon (the theme never makes the bar thinner than 32 px). Presentational:
// it reports a click and the Bar sends quick.toggle. `open` is the quick panel's state (runtime.ui.panel),
// shown as a pressed toggle in the primary button's colours. All colours are component tokens (DESIGN-SYSTEM).
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
        color: q.open
            ? (ma.pressed ? Theme.color("button.primary.bg.pressed", "#ad3741")
               : hover.hovered ? Theme.color("button.primary.bg.hover", "#b93b45")
               : Theme.color("button.primary.bg", "#c9404b"))
            : (ma.pressed ? Theme.color("button.bg.pressed", "#454247")
               : hover.hovered ? Theme.color("button.bg.hover", "#3e3b40")
               : "transparent")
        // The colour eases over the quick motion; the animation runs only while the bar is shown (Ma).
        Behavior on color {
            enabled: q.visible
            ColorAnimation { duration: Theme.quickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve }
        }
    }
    Text {
        anchors.centerIn: parent
        color: q.open ? Theme.color("button.primary.fg", "#fff6f1") : Theme.color("button.fg", "#e9e4d8")
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
        stroke: q.open ? Theme.color("button.primary.fg", "#fff6f1") : Theme.color("focus.ring", "#c9404b")
    }
}
