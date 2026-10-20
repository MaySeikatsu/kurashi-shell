import QtQuick
import qs.core
import qs.components
import ".."

// The lyrics on the desk (`desk:lyrics`, docs/ux/lyrics.md "Design"): caption "LYRICS", the title and artist, then five
// synced lines centred on the current one, or the first lines of plain lyrics. Height 0 while no song plays or nothing
// was found (MODS.md, desk cards: a card with nothing to say is not drawn). The desk has no keyboard focus (K43).
Item {
    // Handed in by ModLoader (K26 loader contract).
    required property var store
    required property var theme
    required property var i18n
    id: dc

    // The card lives only while the desk is shown (its ModLoader is gated on that, Ma), so it watches for its lifetime:
    // the desk hides a card of height 0, and a watch gated on visibility would never see the snapshot that shows it.
    LyricsState { id: lst; live: true }

    readonly property bool wanted: lst.phase === "synced" || lst.phase === "plain"
    implicitHeight: wanted ? card.height : 0

    // The desk's card shape (as Desktop.qml draws its core cards, K43; the tasks mod's DeskCard).
    Block {
        id: card
        visible: dc.wanted
        width: dc.width
        height: body.implicitHeight + 2 * Theme.pad + 2 * inset + Theme.shadowDy
        radius: Theme.rLg + 4
        fill: Theme.surfaceAlpha
        flatBorder: Theme.outline
        Column {
            id: body
            x: Theme.pad
            y: Theme.pad
            width: card.width - 2 * Theme.pad - 2 * card.inset
            spacing: Theme.xs
            Text {
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.weight: Theme.wBold
                font.letterSpacing: 1
                font.capitalization: Font.AllUppercase
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("mod-lyrics.title")
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.weight: Theme.wMedium
                font.family: Theme.fam(text, Theme.families)
                text: (lst.track.title || "") + (lst.track.artist ? " — " + lst.track.artist : "")
            }
            LinesView {
                visible: lst.phase === "synced"
                width: parent.width
                height: visible ? implicitHeight : 0
                ly: lst
                rows: 5
                bigSize: Theme.fs + 3
                smallSize: Theme.fs - 1
                align: Text.AlignLeft
            }
            Text {
                visible: lst.phase === "plain"
                width: parent.width
                wrapMode: Text.Wrap
                maximumLineCount: 6
                elide: Text.ElideRight
                color: Theme.dim
                font.pixelSize: Theme.fs - 1
                font.family: Theme.fam(text, Theme.families)
                text: lst.plain
            }
        }
    }
}
