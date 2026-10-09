import QtQuick
import "../../core"

// media: [art] glyph title — artist, from svc.media. Art only loads while the face is live.
FaceBase {
    id: f
    readonly property var d: Store.docs["svc.media"] || ({})
    readonly property string title: d.title ?? ""
    readonly property string artist: d.artist ?? ""
    readonly property string art: d.art_url ?? ""
    readonly property int maxText: 320
    Watch { doc: "svc.media"; active: f.live }

    wantW: row.implicitWidth
    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.gap - 2
        Image {
            visible: f.art !== "" && status === Image.Ready
            anchors.verticalCenter: parent.verticalCenter
            height: Theme.barH - 18
            width: visible ? height : 0
            // Decoded at display size so a large cover does not sit in memory; the source is
            // only set while live so a hidden face holds no pixmap.
            source: f.live ? f.art : ""
            sourceSize: Qt.size(height * 2, height * 2)
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.accent
            font.pixelSize: Theme.fs
            text: f.d.playing ? "▶" : "⏸"
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            width: Math.min(implicitWidth, f.maxText)
            elide: Text.ElideRight
            text: f.title === "" ? I18n.tr("island.media.idle")
                  : (f.artist === "" ? f.title : f.title + " — " + f.artist)
        }
    }
}
