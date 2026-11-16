import QtQuick
import qs.core
import qs.components

// One picture of the library grid (both pickers): its thumbnail (decoded at 256 px, only while the cell exists — the
// grid is virtualised), the daemon's palette chips, the badges (a look ★, the light or dark half of a pair, the outputs
// showing it), its name under it, a broken file's reason. A cell whose row has not arrived asks for its page. Click
// selects, double-click applies (with the theme while the switch is on).
Item {
    id: cell
    required property int index
    required property var host
    required property GridView grid
    readonly property var row: host.rowAt(index)
    readonly property bool current: GridView.isCurrentItem
    readonly property int nameH: 22
    width: grid.cellWidth
    height: grid.cellHeight

    function ensure() { if (row === null) host.requestPage(host.pageFor(index)) }
    Component.onCompleted: ensure()
    onIndexChanged: ensure()
    Accessible.role: Accessible.ListItem
    Accessible.name: row
        ? row.name + (host.isLook(row) ? ", " + I18n.tr("mod-wallpaper.favourite.mark") : "")
            + (row.on && row.on.length > 0 ? ", " + I18n.tr("mod-wallpaper.on") + " " + row.on.join(", ") : "")
        : ""
    Accessible.selected: current

    Rectangle {
        id: tile
        anchors.fill: parent
        anchors.margins: 4
        radius: Theme.rSm
        color: Theme.container
        // The selected picture is ringed in the accent; hover a hairline (quiet states, I83).
        border.width: cell.current ? 2 : (tileHover.hovered ? 1 : 0)
        border.color: cell.current ? Theme.accent : Theme.outline
        clip: true

        Image {
            id: thumb
            Component.onCompleted: Light.addPicture(thumb, Window.window)
            Component.onDestruction: Light.removePicture(thumb)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: tile.border.width
            height: parent.height - cell.nameH - tile.border.width
            source: cell.row && cell.row.thumb ? cell.host.fileUrl(cell.row.thumb) : ""
            sourceSize.width: 256
            sourceSize.height: 256
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            visible: source !== ""
        }
        // Palette chips: the daemon's, computed from the image's own colours.
        Row {
            anchors.left: parent.left
            anchors.bottom: thumb.bottom
            anchors.margins: 5
            spacing: 2
            visible: cell.row !== null && cell.row.palette !== undefined
            Repeater {
                model: cell.row && cell.row.palette ? cell.row.palette : []
                delegate: Rectangle {
                    required property string modelData
                    width: 10
                    height: 10
                    radius: 2
                    color: modelData
                    border.width: 1
                    border.color: Theme.surface
                }
            }
        }
        // Badges: the light or dark half of a pair (left); a look ★ and the output(s) showing it (right).
        Chip {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 5
            visible: cell.row !== null && cell.row.pair !== undefined
            text: cell.row && cell.row.pair ? I18n.tr("mod-wallpaper.pair." + cell.row.pair.role) : ""
            fg: Theme.fg
            bg: Theme.surfaceAlpha
            edge: Theme.outline
        }
        Row {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 5
            spacing: 3
            Chip {
                visible: cell.row !== null && cell.host.isLook(cell.row)
                text: "★"
                fg: Theme.accent
                bg: Theme.surfaceAlpha
                edge: Theme.accent
            }
            Chip {
                visible: cell.row !== null && cell.row.on !== undefined && cell.row.on.length > 0
                text: cell.row && cell.row.on ? "● " + cell.row.on.join(" ") : ""
                fg: Theme.fg
                bg: Theme.surfaceAlpha
                edge: Theme.outline
            }
        }
        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            height: cell.nameH
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideMiddle
            color: cell.row && cell.row.error ? Theme.error : (cell.current ? Theme.fg : Theme.dim)
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: {
                if (cell.row === null) return ""
                if (cell.row.error) return I18n.tr(cell.row.error)
                return cell.row.name
            }
        }
        Text {
            anchors.centerIn: thumb
            visible: cell.row === null || cell.row.error !== undefined
            color: cell.row && cell.row.error ? Theme.error : Theme.dim
            font.pixelSize: Theme.fsTitle
            text: cell.row && cell.row.error ? "!" : "…"
        }
        FocusRing { anchors.fill: parent; corner: tile.radius; shown: cell.grid.activeFocus && cell.current }
        HoverHandler { id: tileHover }
        TapHandler {
            onTapped: { cell.grid.currentIndex = cell.index; cell.grid.forceActiveFocus() }
            onDoubleTapped: {
                cell.grid.currentIndex = cell.index
                cell.host.applyRow(cell.row, false, cell.host.withTheme, cell.host.originOf(tile))
            }
        }
    }
}
