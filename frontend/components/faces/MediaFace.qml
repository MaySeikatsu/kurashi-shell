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
    // The title's most width (B48: a bar's fit lowers it in a tight zone, through the island's `textRoom`).
    property real maxText: 320
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
            id: playIcon
            visible: f.title === "" || f.d.playing !== true
            anchors.verticalCenter: parent.verticalCenter
            name: f.title === "" ? "music_note" : "pause"
            glyph: f.title === "" ? "♪" : "⏸"
            filled: true
            size: Theme.fs + 3
            color: f.title === "" ? Theme.dim : Theme.accent
        }
        LevelBars {
            id: bars
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
            id: titleT
            width: Math.min(implicitWidth, f.maxText)
            elide: Text.ElideRight
            text: f.full
        }
    }
    // B48 (docs/ux/bar-fit.md): the title as the bar's fit sees it — what it takes at its cap, and now.
    readonly property real textNat: f.vertical ? 0 : Math.min(titleT.implicitWidth, 320)
    readonly property real textShown: f.vertical ? 0 : titleT.width
    // The row without its title, from its parts (the row's own width follows a title change a frame late).
    readonly property real rowChrome: {
        var parts = [cover.visible ? cover.width : -1, playIcon.visible ? playIcon.implicitWidth : -1, bars.visible ? bars.width : -1]
        var w = 0, n = 1
        for (var i = 0; i < parts.length; i++) if (parts[i] >= 0) { w += parts[i]; n++ }
        return w + (n - 1) * row.spacing
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
