import QtQuick
import "../../../core"
import "../.."
import ".."

// Mark (W53.4): the menu bar's first item — where Mac OS X and macOS put the Apple menu (docs/ux/styles.md §5, §6) — as
// our original mark (MenuMark: 暮's setting sun, never Apple's logo) in `[decor] start.fill` with `start.gloss` (Jaguar's
// blue gel; 0 = macOS 11+'s flat glyph in the text's ink). No label. While the launcher is open it is a menu title held
// open: under `menu.highlight = bar` the full-height band in `menu.fill` (Aqua's blue gel, `menu.gloss`) with the mark
// in `menu.on`; otherwise an inset rounded highlight (macOS 11+). Its skin opens the launcher as that menu: `DropMenu`
// (a pull-down hanging from the bar, Aqua) or `Popover` (a vibrancy panel, macOS 11+) — chosen by the same metric, so
// the part never knows a look (rule 4). Static (0 frames idle).
StartBase {
    id: st
    property real thickness: Theme.barH
    readonly property bool band: Theme.decor("menu.highlight", "capsule") === "bar"
    menu: band ? Qt.resolvedUrl("DropMenu.qml") : Qt.resolvedUrl("Popover.qml")
    signal clicked()

    readonly property var fills: Theme.decor("start.fill", [])
    readonly property color c: fills.length > 0 ? fills[0] : Theme.fg
    readonly property real g: Theme.decor("start.gloss", 0)
    readonly property bool lit: open || pressed || hit.pressed
    readonly property string hiRole: Theme.decor("menu.fill", "")
    readonly property color hi: hiRole !== "" ? hiRole : Theme.accent
    readonly property string inkRole: Theme.decor("menu.on", "")
    readonly property color hiInk: inkRole !== "" ? inkRole : Theme.fgOnAccent
    readonly property real mg: Theme.decor("menu.gloss", 0)
    readonly property real h: Math.max(16, Math.round(thickness))
    implicitHeight: h
    implicitWidth: vertical ? h : Math.round(Math.max(28, h * 1.45))
    width: implicitWidth
    height: implicitHeight

    Accessible.role: Accessible.Button
    Accessible.name: I18n.tr("layout.module.launcher")
    Accessible.onPressAction: st.clicked()

    // The held-open band (Aqua): the bar's height, the gel's light top, the colour, a deeper foot.
    Rectangle {
        anchors.fill: parent
        visible: st.lit && st.band
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(st.hi, 1 + 0.45 * st.mg) }
            GradientStop { position: 0.5; color: Qt.lighter(st.hi, 1 + 0.12 * st.mg) }
            GradientStop { position: 0.51; color: st.hi }
            GradientStop { position: 1; color: Qt.darker(st.hi, 1 + 0.12 * st.mg) }
        }
    }
    // The inset highlight (macOS 11+): a rounded rect of the text's ink, faint, 3 px off the bar's edges.
    Rectangle {
        anchors { fill: parent; topMargin: 3; bottomMargin: 3; leftMargin: 1; rightMargin: 1 }
        visible: (st.lit || hit.containsMouse) && !st.band
        radius: 4
        color: Qt.alpha(Theme.fg, st.lit ? 0.16 : 0.08)
    }
    MenuMark {
        anchors.centerIn: parent
        size: Math.round(Math.min(st.h * 0.66, 18))
        color: st.lit && st.band ? st.hiInk : st.c
        gloss: st.lit && st.band ? 0 : st.g
    }
    FocusRing {
        anchors.fill: parent
        anchors.margins: 2
        shown: st.activeFocus
    }
    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        onClicked: st.clicked()
    }
}
