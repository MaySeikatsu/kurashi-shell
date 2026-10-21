import QtQuick
import "../core"

// TileSheet (K59): a window's copy of the material tile, as two render targets of the tile's size: the normal and
// cavity map (`normal`) and the ink map (`ink`). Every Relief of the window samples them, so a window holds one pair
// however many blocks it has (docs/ux/texture.md "Budget").
//
// Why render targets and not Images: Qt Quick premultiplies every texture with alpha (an alpha-0 texel loses its RGB,
// where the normal lives), and packs small plain images into a shared atlas whose sub-rectangle a shader's own texel
// coordinates miss. A ShaderEffectSource is a texture of its own, filled from its Image: `live` redraws it with each
// frame of its window (one small blit per frame of a visible window, none for a window that is not drawn), which keeps
// it current when the tile arrives late or changes size. It is parked outside its window: a texture provider needs its
// paint node, and nothing draws it.
//
// A surface shares its sheet by naming it on its window (`property var tileSheet: <this>`, read by Relief through
// QsWindow); a Relief in a window without one makes its own, which costs a pair per Relief.
Item {
    id: sheet

    readonly property var normal: normalSrc
    readonly property var ink: inkSrc
    readonly property int side: Theme.texTilePx

    x: -100000
    y: -100000
    width: side
    height: side

    Image {
        id: normalImg
        width: sheet.side
        height: sheet.side
        fillMode: Image.Stretch
        smooth: false
        asynchronous: false
        cache: true
        source: Theme.texMap !== "" ? "file://" + Theme.texMap : ""
        onStatusChanged: if (status === Image.Ready) sheet.fill()
    }
    ShaderEffectSource {
        id: normalSrc
        sourceItem: normalImg
        hideSource: true
        live: false
        width: sheet.side
        height: sheet.side
        textureSize: Qt.size(sheet.side, sheet.side)
    }

    Image {
        id: inkImg
        width: sheet.side
        height: sheet.side
        fillMode: Image.Stretch
        smooth: false
        asynchronous: false
        cache: true
        source: Theme.texInkMap !== "" ? "file://" + Theme.texInkMap : ""
        onStatusChanged: if (status === Image.Ready) sheet.fill()
    }
    ShaderEffectSource {
        id: inkSrc
        sourceItem: inkImg
        hideSource: true
        live: false
        width: sheet.side
        height: sheet.side
        textureSize: Qt.size(sheet.side, sheet.side)
    }

    // A copy is drawn while it is live, and a live copy keeps its window drawing frames: each fill runs live for a moment
    // and then stays as drawn, so an idle window draws nothing (Ma).
    function fill() {
        normalSrc.live = true
        inkSrc.live = true
        settle.restart()
    }
    Timer {
        id: settle
        interval: 250
        onTriggered: {
            normalSrc.live = false
            inkSrc.live = false
        }
    }

    Component.onCompleted: {
        console.log("texture: tile sheet made")
        fill()
    }
}
