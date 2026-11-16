import QtQuick
import qs.core
import qs.components

// The library as a grid (both pickers), or the state in its place. Virtualised: delegates exist for the visible cells
// only (Tile.qml asks for its page). Columns of about 220 px where there is room, never fewer than `least` (I538).
// `tabTo` / `backTo`: where Tab and Shift+Tab go from the grid (the preview's actions, the search field), so the focus
// does not leave the picker for the host's next control (I32).
Item {
    id: lg
    required property var host
    property int least: 2
    property Item tabTo: null
    property Item backTo: null
    readonly property alias grid: gv
    readonly property real cellH: gv.cellHeight
    clip: true

    EmptyState {
        visible: !lg.host.showGrid
        anchors.centerIn: parent
        width: parent.width - Theme.pad * 2
        host: lg.host
        large: lg.height > 200
    }
    GridView {
        id: gv
        objectName: "wall-grid"
        KineticWheel { view: gv }
        anchors.fill: parent
        visible: lg.host.showGrid
        clip: true
        focus: true
        activeFocusOnTab: true
        keyNavigationEnabled: true
        KeyNavigation.tab: lg.tabTo
        KeyNavigation.backtab: lg.backTo
        highlightMoveDuration: Theme.quickMs
        model: lg.host.total
        cellWidth: Math.floor(width / lg.host.columnsFor(width, lg.least))
        cellHeight: Math.round((cellWidth - 8) * 9 / 16) + 22 + 8
        boundsBehavior: Flickable.StopAtBounds
        Accessible.role: Accessible.List
        Accessible.name: I18n.tr("appearance-menu.wallpaper.grid")
        Keys.onPressed: event => lg.host.gridKey(event)
        delegate: Tile {
            host: lg.host
            grid: gv
        }
    }
    ScrollEdge { view: gv }
}
