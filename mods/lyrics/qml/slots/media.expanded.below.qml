import QtQuick
import qs.core
import qs.components
import ".."

// The lyrics under the media card's transport (slot `media.expanded.below`, docs/ux/lyrics.md "Design"): three synced
// lines that follow the song (the current one large), a scrollable text for plain lyrics, or one dim line that says
// why there are none ("Try again" when the lookup failed). Lives while the card is open (Ma): its state watches and
// wakes only then. Hidden (height 0) while nothing plays.
Item {
    // Handed in by ModLoader (K26 loader contract).
    required property var store
    required property var theme
    required property var i18n
    id: slot

    LyricsState { id: lst; live: slot.visible }

    readonly property string phase: lst.phase
    readonly property bool message: phase === "searching" || phase === "none" || phase === "instrumental"
        || phase === "offline" || phase === "error"

    width: parent ? parent.width : 0
    implicitHeight: phase === "hidden" ? 0 : col.implicitHeight
    height: implicitHeight

    Column {
        id: col
        width: slot.width
        visible: slot.phase !== "hidden"
        spacing: Theme.xs

        LinesView {
            visible: slot.phase === "synced"
            width: parent.width
            height: visible ? implicitHeight : 0
            ly: lst
            rows: 3
        }

        // Plain lyrics: four lines tall, scrolled by the user.
        Flickable {
            id: flick
            visible: slot.phase === "plain"
            width: parent.width
            height: visible ? Math.min(plainText.implicitHeight, Math.round(Theme.fs * 1.5) * 4) : 0
            contentHeight: plainText.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Text {
                id: plainText
                width: flick.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                lineHeight: 1.15
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: lst.plain
            }
        }

        Row {
            visible: slot.message
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.gap
            height: Math.max(msg.implicitHeight, retry.visible ? retry.implicitHeight : 0)
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: slot.phase === "offline" ? "cloud_off" : slot.phase === "error" ? "error" : "lyrics"
                glyph: "♪"
                color: slot.phase === "error" ? Theme.error : Theme.dim
                size: Theme.fs + 2
            }
            Text {
                id: msg
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, col.width - (retry.visible ? retry.implicitWidth + Theme.gap : 0) - Theme.fs - 2 * Theme.gap)
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: slot.phase === "error" ? Theme.error : Theme.dim
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: slot.phase === "searching" ? I18n.tr("mod-lyrics.searching")
                    : slot.phase === "instrumental" ? I18n.tr("mod-lyrics.instrumental")
                    : lst.reasonText !== "" ? lst.reasonText : I18n.tr("mod-lyrics.none")
            }
            Button {
                id: retry
                anchors.verticalCenter: parent.verticalCenter
                visible: slot.phase === "offline" || slot.phase === "error"
                label: I18n.tr("mod-lyrics.retry")
                icon: "refresh"
                onClicked: lst.retry()
            }
        }
    }
}
