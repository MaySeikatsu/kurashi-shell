import QtQuick
import qs.core
import qs.components

// Bar widget of the lyrics mod (docs/ux/lyrics.md "Design"): a note icon and the line being sung, elided at 280 px.
// Shown only while synced lines are; zero size otherwise (searching, plain, instrumental, none: the bar keeps its room).
// `mods.lyrics.bar_line` off: the icon only. A side bar: the icon only. Click (Return, Enter, Space) opens the island's
// expanded view, where the media card shows the full lyrics.
Item {
    // Handed in by ModLoader (K26 loader contract).
    required property var store
    required property var theme
    required property var i18n
    id: w
    property bool vertical: false

    // The widget lives while it is placed: it must keep watching to learn when lyrics arrive (a watch gated on its own
    // visibility would never see the change that shows it).
    LyricsState { id: ly; live: true }

    readonly property bool shown: ly.phase === "synced"
    readonly property bool showLine: shown && ly.barLine && !w.vertical
    readonly property string line: ly.currentText !== "" ? ly.currentText : "♪"

    visible: shown
    implicitWidth: !shown ? 0 : w.vertical ? Theme.barH : row.implicitWidth + Theme.gap * 2
    implicitHeight: !shown ? 0 : Theme.controlH
    activeFocusOnTab: shown
    Accessible.role: Accessible.Button
    Accessible.name: I18n.tr("mod-lyrics.a11y.widget").replace("{line}",
        ly.currentText !== "" ? ly.currentText : I18n.tr("mod-lyrics.a11y.pause"))

    function open() { Store.act("island.expand", {}) }
    Keys.onReturnPressed: w.open()
    Keys.onEnterPressed: w.open()
    Keys.onSpacePressed: w.open()

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.xs
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "lyrics"
            glyph: "♪"
            color: Theme.fg
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: w.showLine
            width: Math.min(implicitWidth, 280)
            elide: Text.ElideRight
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: w.line
        }
    }

    FocusRing { anchors.fill: parent; shown: w.activeFocus; corner: Theme.rSm }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: w.open()
    }
}
