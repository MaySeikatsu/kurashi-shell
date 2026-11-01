import QtQuick
import "../../core"

// Box (W53.8, docs/ux/styles.md "terminal"): a card as a text-mode window — the box a TUI draws round a panel with the
// type's box-drawing characters (htop's and mc's panels, a dialog(1) box), here as the lines those glyphs make: half a
// character cell inside the card, one device pixel wide (the stroke of a box-drawing glyph at body size), in the
// outline's ink. `[decor] frame.box`: `single` ┌─┐, `double` ╔═╗ (two strokes two pixels apart), `round` ╭─╮ (the
// corner a half cell's arc). Small blocks (keys, tiles, bar groups) keep the chrome's own line; with `none` the frame
// draws nothing. The card's straight outline steps aside while the box draws (FrameBase.drawsOutline). Static.
FrameBase {
    id: f
    readonly property string form: Theme.decor("frame.box", "none")
    readonly property bool draws: f.card && form !== "none"
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    // Half a character cell of the body face (JetBrains Mono at 13 px: 7.8 px wide → 4 px).
    readonly property real half: Math.max(3, Math.round(fm.averageCharacterWidth / 2))
    readonly property color ink: Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline
    drawsOutline: draws
    FontMetrics { id: fm; font.family: Theme.families[0]; font.pixelSize: Theme.fs }

    Rectangle {
        visible: f.draws
        anchors.fill: parent
        anchors.margins: f.half
        color: "transparent"
        antialiasing: f.form === "round"
        radius: f.form === "round" ? f.half : 0
        border.width: f.hair
        border.color: f.ink
    }
    Rectangle {
        visible: f.draws && f.form === "double"
        anchors.fill: parent
        anchors.margins: f.half + 3 * f.hair
        color: "transparent"
        antialiasing: false
        border.width: f.hair
        border.color: f.ink
    }
}
