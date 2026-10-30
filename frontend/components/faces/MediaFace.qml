import QtQuick
import "../../core"
import ".."
import "../island"

// media: [art] glyph title — artist, from svc.media. Art only loads while the face is live. On a side bar the
// play state alone: the title is the column's accessible name and the peek's line.
FaceBase {
    id: f
    readonly property var raw: Store.docs["svc.media"] || ({})
    // available:false means the MPRIS stream is gone, which is not "no players": show nothing from
    // it, so the face reads as idle (the same as an empty player list).
    readonly property var d: raw.available === false ? ({}) : raw
    readonly property string title: d.title ?? ""
    readonly property string artist: d.artist ?? ""
    readonly property string art: d.art_url ?? ""
    readonly property string full: title === "" ? I18n.tr("island.media.idle")
        : (artist === "" ? title : title + " — " + artist)
    readonly property int maxText: 320
    Watch { doc: "svc.media"; active: f.live }

    wantW: row.implicitWidth
    wantH: col.implicitHeight
    Row {
        id: row
        visible: !f.vertical
        anchors.centerIn: parent
        spacing: Theme.gap - 2
        Image {
            id: cover
            visible: f.art !== "" && status === Image.Ready
            // I167: the cover is a picture: never under the relief, even with texture.text on.
            readonly property var pictureOf: status === Image.Ready ? Window.window : null
            onPictureOfChanged: pictureOf ? Light.addPicture(cover, pictureOf) : Light.removePicture(cover)
            Component.onDestruction: Light.removePicture(cover)
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
        // Play state only while something is loaded; with no player the face is idle, not paused. Playing: the level bars
        // move (W21; only while this face is live and motion is on); paused: they rest beside a pause icon.
        Icon {
            visible: f.title === "" || f.d.playing !== true
            anchors.verticalCenter: parent.verticalCenter
            name: f.title === "" ? "music_note" : "pause"
            glyph: f.title === "" ? "♪" : "⏸"
            filled: true
            size: Theme.fs + 3
            color: f.title === "" ? Theme.dim : Theme.accent
        }
        LevelBars {
            visible: f.title !== ""
            anchors.verticalCenter: parent.verticalCenter
            running: f.d.playing === true && f.live && f.current && f.animate
            maxH: Theme.fs
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            width: Math.min(implicitWidth, f.maxText)
            elide: Text.ElideRight
            text: f.full
        }
    }
    Column {
        id: col
        visible: f.vertical
        anchors.centerIn: parent
        Accessible.role: Accessible.StaticText
        Accessible.name: f.full
        Icon {
            Accessible.ignored: true
            color: f.title === "" ? Theme.dim : Theme.accent
            name: f.title === "" ? "music_note" : (f.d.playing ? "play_arrow" : "pause")
            glyph: f.title === "" ? "♪" : (f.d.playing ? "▶" : "⏸")
            filled: true
            size: Theme.fs + 3
        }
    }
}
