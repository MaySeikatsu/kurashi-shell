import QtQuick
import "../../core"

// PixelLabel (W53.1): one line of text that honours bitmap type (`Theme.pixelType`): native rendering, full hinting and no
// smoothing — one ink on whole pixels. Bold under bitmap type is drawn as the bitmap era drew it (GDI's overstrike): the
// regular face twice, 1 px apart, every advance 1 px wider — a synthetic outline bold smears a pixel face's letters into
// each other. Outside bitmap type it is a plain Text at `weight`. For decor parts; callers keep their own Text.
Item {
    id: pl
    property string text: ""
    property color color: Theme.fg
    property int pixelSize: Theme.fs
    property int weight: Theme.wRegular
    property int elide: Text.ElideRight
    property int horizontalAlignment: Text.AlignLeft
    readonly property bool overstrike: Theme.pixelType && weight >= 600
    implicitWidth: ink.implicitWidth + (overstrike ? 1 : 0)
    implicitHeight: ink.implicitHeight

    Text {
        id: ink
        width: pl.width > 0 ? pl.width - (pl.overstrike ? 1 : 0) : implicitWidth
        anchors.verticalCenter: parent.verticalCenter
        text: pl.text
        color: pl.color
        elide: pl.elide
        horizontalAlignment: pl.horizontalAlignment
        font.family: Theme.fam(pl.text, Theme.families)
        font.pixelSize: pl.pixelSize
        font.weight: pl.overstrike ? Theme.wRegular : pl.weight
        font.letterSpacing: pl.overstrike ? 1 : 0
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
    }
    Loader {
        active: pl.overstrike
        x: ink.x + 1
        y: ink.y
        sourceComponent: Text {
            width: ink.width
            text: ink.text
            color: ink.color
            elide: ink.elide
            horizontalAlignment: ink.horizontalAlignment
            font: ink.font
            renderType: ink.renderType
            antialiasing: false
        }
    }
}
