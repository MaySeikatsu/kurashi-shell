import QtQuick
import "../../core"
import ".."
import "appearance.js" as A

// The options of a choice the theme previews (`theme.previews`: palettes, styles, looks — K53), each drawn in its own
// tokens as Settings' cards are: a palette as five dots, a style or look as a small card (its surface, accent, text and
// corner). An option the previews lack (the wallpaper's palette, "your own") is a plain tile with its name. One strip that
// scrolls sideways, so a pane keeps its other rows in view however many options there are (macOS' and Windows' strips);
// the chosen one is kept in view. The row around it holds the focus; Left/Right (the row's) move and preview.
ListView {
    id: tl
    property var cards: []            // the previews' list for this source
    property var choices: []          // the row's options ({value, label})
    property var current: undefined
    property bool focused: false
    property bool dots: false         // palettes: five dots; else a small card
    signal picked(var value)

    readonly property int tileW: dots ? 124 : 112
    readonly property int chosenIndex: {
        for (var i = 0; i < choices.length; i++) if (A.same(choices[i].value, current)) return i
        return -1
    }
    function cardOf(v) {
        for (var i = 0; i < cards.length; i++) if (cards[i].name === v) return cards[i]
        return null
    }
    function reveal() { if (chosenIndex >= 0) positionViewAtIndex(chosenIndex, ListView.Contain) }
    onChosenIndexChanged: reveal()
    Component.onCompleted: Qt.callLater(reveal)

    orientation: ListView.Horizontal
    height: dots ? 58 : 86
    spacing: Theme.gap
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: choices
    Accessible.role: Accessible.List
    ScrollEdge { view: tl; horizontal: true }

    delegate: Rectangle {
        id: tile
        required property var modelData
        required property int index
        readonly property var card: tl.cardOf(modelData.value)
        readonly property var tk: card ? card.tokens || ({}) : ({})
        function tc(k, d) { var v = tile.tk[k]; return v === undefined || v === "" ? d : v }
        readonly property bool chosen: index === tl.chosenIndex
        width: tl.tileW
        height: tl.height
        radius: Theme.rSm + 2
        color: Theme.containerHigh
        border.width: chosen ? 2 : 1
        border.color: chosen ? Theme.accent : Theme.outline
        Accessible.role: Accessible.RadioButton
        Accessible.name: label.text
        Accessible.checkable: true
        Accessible.checked: chosen

        // a palette: its five colours
        Row {
            visible: tl.dots
            x: 10; y: 10
            spacing: -4
            Repeater {
                model: tl.dots && tile.card ? ["color.accent", "color.secondary", "color.tertiary", "color.surface", "color.on_surface"] : []
                delegate: Rectangle {
                    required property string modelData
                    width: 18; height: 18; radius: 9
                    color: tile.tc(modelData, "#808080")
                    border.width: 1
                    border.color: Qt.alpha("#000000", 0.25)
                }
            }
        }
        // a style or look: a card in its tokens
        Rectangle {
            visible: !tl.dots && tile.card !== null
            x: 8; y: 8
            width: parent.width - 16
            height: parent.height - 32
            radius: Math.min(height / 3, Number(tile.tc("radius.sm", 6)))
            color: tile.tc("color.surface", "#202020")
            border.width: Math.max(1, Math.min(2, Number(tile.tc("chrome.outline", 1))))
            border.color: tile.tc("chrome.outline_color", tile.tc("color.surface_container_high", "#404040"))
            Rectangle { x: 6; y: 6; width: parent.width * 0.42; height: 6; radius: 3; color: tile.tc("color.accent", "#c9404b") }
            Rectangle { x: 6; y: 17; width: parent.width - 12; height: 4; radius: 2; color: tile.tc("color.on_surface", "#e0e0e0"); opacity: 0.8 }
            Rectangle { x: 6; y: 25; width: parent.width * 0.6; height: 4; radius: 2; color: tile.tc("color.on_surface_variant", "#a0a0a0"); opacity: 0.8 }
            Rectangle {
                anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 5
                width: 14; height: 8; radius: 4
                color: tile.tc("color.selected", tile.tc("color.accent", "#c9404b"))
            }
        }
        // an option with no card: its mark
        Icon {
            visible: tile.card === null
            x: 10; y: tl.dots ? 8 : 18
            name: "image"
            glyph: "▦"
            size: tl.dots ? 22 : 30
            color: Theme.dim
        }
        Text {
            id: label
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8; bottomMargin: 6 }
            elide: Text.ElideRight
            color: Theme.fg
            font.pixelSize: Theme.fsCaption
            font.weight: tile.chosen ? Theme.wBold : Theme.wRegular
            font.family: Theme.fam(text, Theme.families)
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            text: I18n.tr(tile.modelData.label !== undefined ? tile.modelData.label : String(tile.modelData.value))
        }
        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.fg
            opacity: hov.hovered ? 0.06 : 0
        }
        TapHandler { onTapped: tl.picked(tile.modelData.value) }
        FocusRing { anchors.fill: parent; corner: tile.radius; shown: tl.focused && tile.chosen }
    }
}
