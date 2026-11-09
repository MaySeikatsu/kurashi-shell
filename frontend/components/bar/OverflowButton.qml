import QtQuick
import Quickshell
import "../../core"
import ".."
import "../island"

// The bar's overflow (B48, docs/ux/bar-fit.md): "…" and how many of the zone's modules gave way, at the zone's inner end
// while there are any. A click (Enter, Space) opens the card with them (Bar.qml `openOverflow`). Its width is fixed
// (`widthFor`): the fit counts it before it exists.
Item {
    id: ob
    property int count: 0
    property string zone: ""
    property string output: ""
    property bool open: false
    signal clicked()

    // The width the fit reserves for it: the glyph, a gap and two digits, and a gap a side.
    function widthFor() { return Math.round(Theme.iconSize * Theme.iconScale) + Theme.xs + Math.ceil(digitsM.advanceWidth) + 2 * Theme.gap }
    TextMetrics { id: digitsM; text: "99"; font.pixelSize: Theme.fsCaption; font.weight: Theme.wBold; font.family: Theme.fam(text, Theme.families) }
    width: widthFor()
    // (as tall as the keyboard chip: its pressed square stays inside the group's block)
    height: Theme.barH - 12

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: I18n.tr("frontend.bar.overflow").replace("{n}", ob.count)
    Keys.onReturnPressed: ob.clicked()
    Keys.onEnterPressed: ob.clicked()
    Keys.onSpacePressed: ob.clicked()

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: ob.clicked() }
    // The card a press opens comes out of it (`module:overflow`, as every module's origin).
    AnchorReport { target: ob; key: "module:overflow"; output: ob.output; enabled: ob.output !== "" }

    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        color: ob.open ? Theme.containerHigh : (hover.hovered ? Theme.containerHigh : "transparent")
        border.width: ob.open ? Theme.outlineW : 0
        border.color: Theme.outline
    }
    Row {
        anchors.centerIn: parent
        spacing: Theme.xs
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "more_horiz"
            glyph: "…"
            color: Theme.fg
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.weight: Theme.wBold
            font.family: Theme.fam(text, Theme.families)
            font.features: ({ "tnum": 1 })
            text: String(ob.count)
        }
    }
    FocusRing {
        anchors.fill: parent
        corner: Theme.rSm
        shown: ob.activeFocus
    }
}
