import QtQuick
import "../../../core"
import "../.."
import ".."

// Tab (W53.6): the start dress as a game menu's tab — NieR:Automata's header tabs (a word in capitals with its square
// bullet; the open tab an inverted block in `[decor] menu.fill` with the word in `menu.on`), and any look that wants a
// word with a mark rather than a button: the mark is `start.mark` (Bullet.qml), the word `start.label`'s (`start.word`:
// "Start" or "Menu") in `font.start` (`start.family`, else the title's face) at `start.size`, in capitals while
// `title.caps`. Hover draws the look's resting band (`menu.rest`); pressed or open, the block. On a side bar only the mark.
// From tokens only (rule 4); static (0 frames idle). Contract: StartBase + the `launcher` module's `thickness`/`clicked`.
StartBase {
    id: st
    property real thickness: Theme.barH
    // The start-menu skin (`[decor] start.skin`): a framed panel or a veil without a box (no banner either way).
    menu: Qt.resolvedUrl(Theme.pascal(Theme.decor("start.skin", "panel")) + ".qml")
    signal clicked()

    readonly property bool down: pressed || open || hit.pressed
    readonly property bool hot: hit.containsMouse && !down
    readonly property bool showLabel: label !== "" && !vertical
    readonly property real h: Math.max(16, Math.round(thickness))
    readonly property string fillRole: Theme.decor("menu.fill", "")
    readonly property string onRole: Theme.decor("menu.on", "")
    readonly property string restRole: Theme.decor("menu.rest", "")
    readonly property color ink: down ? (onRole !== "" ? onRole : Theme.fgOnSelected) : Theme.fg
    readonly property real pad: Math.round(h * 0.45)
    readonly property bool caps: Theme.decor("title.caps", false) === true
    implicitHeight: h
    implicitWidth: vertical ? h : pad + (mark.visible ? mark.width : 0) + (showLabel ? (mark.visible ? Math.round(h * 0.28) : 0) + Math.ceil(word.implicitWidth) : 0) + pad
    width: implicitWidth
    height: implicitHeight

    Accessible.role: Accessible.Button
    Accessible.name: label !== "" ? label : I18n.tr("layout.module.launcher")
    Accessible.onPressAction: st.clicked()

    // W53.6: with `start.fill` the tab is a box — the fill, outlined `border.line_width` px in `border.line` on its top and
    // sides with a light foot (Needy Streamer Overload's START: violet over a pale orchid face, white along the bottom).
    readonly property var boxFill: Theme.decor("start.fill", [])
    readonly property string lineRole: Theme.decor("border.line", "")
    readonly property int lw: Math.max(1, Theme.decor("border.line_width", 1))
    Rectangle {
        visible: st.boxFill.length > 0
        anchors { fill: parent; topMargin: Math.round(st.h * 0.18); bottomMargin: Math.round(st.h * 0.12) }
        color: st.down ? Qt.darker(st.boxFill.length > 0 ? st.boxFill[0] : "transparent", 1.08)
                       : (st.boxFill.length > 0 ? st.boxFill[0] : "transparent")
        antialiasing: false
        Rectangle { width: parent.width; height: st.lw; color: st.lineRole !== "" ? st.lineRole : Theme.outline }
        Rectangle { width: st.lw; height: parent.height; color: st.lineRole !== "" ? st.lineRole : Theme.outline }
        Rectangle { x: parent.width - st.lw; width: st.lw; height: parent.height; color: st.lineRole !== "" ? st.lineRole : Theme.outline }
        Rectangle { y: parent.height - st.lw; width: parent.width; height: st.lw; color: Theme.color("color.surface_container_lowest", "#ffffff") }
    }
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: Math.round(st.h * 0.14)
        anchors.bottomMargin: Math.round(st.h * 0.14)
        visible: st.boxFill.length === 0 && (st.down || (st.hot && st.restRole !== ""))
        radius: Math.max(0, Theme.decor("menu.radius", -1))
        color: st.down ? (st.fillRole !== "" ? st.fillRole : Theme.selected)
                       : (st.restRole !== "" ? st.restRole : "transparent")
    }
    Bullet {
        id: mark
        kind: Theme.decor("start.mark", "none") !== "none" ? Theme.decor("start.mark", "none") : (st.showLabel ? "none" : "square")
        ink: st.ink
        size: Math.max(5, Math.round(st.h * 0.22))
        x: st.vertical ? Math.round((st.width - width) / 2) : st.pad
        y: Math.round((st.height - height) / 2)
    }
    Text {
        id: word
        visible: st.showLabel
        x: mark.visible ? mark.x + mark.width + Math.round(st.h * 0.28) : st.pad
        anchors.verticalCenter: parent.verticalCenter
        text: st.caps ? st.label.toUpperCase() : st.label
        color: st.ink
        font.family: Theme.tok("font.start", "") || Theme.tok("font.title", "") || Theme.fam(st.label, Theme.families)
        font.pixelSize: Theme.decor("start.size", 0) > 0 ? Theme.decor("start.size", 0) : Theme.fs
        font.weight: Theme.decor("title.weight", 600)
        font.letterSpacing: st.caps ? Math.round(font.pixelSize * 0.12) : 0
        font.italic: Theme.decor("start.italic", false) === true
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
    }
    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        onClicked: st.clicked()
    }
}
