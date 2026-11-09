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
    // B48 (docs/ux/bar-fit.md, the widget's fit): elastic — the line elides to the bar's `room`, at its own cap of 280 px;
    // with less than a few letters' room only the note is drawn. The widths from metrics (a hidden text is not laid out).
    property real room: 1e6
    readonly property real noteW: noteIcon.implicitWidth
    TextMetrics { id: lineM; text: w.line; font.pixelSize: Theme.fs; font.family: Theme.fam(text, Theme.families) }
    readonly property real lineNat: w.showLine ? Math.min(280, Math.ceil(lineM.advanceWidth)) : 0
    readonly property real lineRoom: Math.min(w.lineNat, w.room - w.noteW - Theme.xs - Theme.gap * 2)
    readonly property bool lineFits: w.showLine && w.lineRoom >= Math.min(w.lineNat, 40)
    readonly property bool elastic: w.showLine && !w.vertical
    readonly property real fullWidth: !shown ? 0 : w.noteW + (w.showLine ? Theme.xs + w.lineNat : 0) + Theme.gap * 2
    readonly property real minWidth: !shown ? 0 : w.noteW + Theme.gap * 2
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
            id: noteIcon
            anchors.verticalCenter: parent.verticalCenter
            name: "lyrics"
            glyph: "♪"
            color: Theme.fg
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: w.lineFits
            width: Math.max(0, Math.floor(w.lineRoom))
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
