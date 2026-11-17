import QtQuick
import qs.core

// The library's order and filter: Name, Newest, Random (a new shuffle each press, R in the grid), and ★ Looks (only
// the pictures kept as looks).
ChipRow {
    id: sc
    Accessible.role: Accessible.Grouping
    PickButton {
        objectName: "wall-sort-name"
        label: I18n.tr("mod-wallpaper.sort.name")
        selected: sc.host.sort === "name"
        onActivated: sc.host.sort = "name"
    }
    PickButton {
        objectName: "wall-sort-newest"
        label: I18n.tr("mod-wallpaper.sort.newest")
        selected: sc.host.sort === "newest"
        onActivated: sc.host.sort = "newest"
    }
    PickButton {
        objectName: "wall-sort-random"
        label: I18n.tr("mod-wallpaper.random")
        selected: sc.host.sort === "random"
        enabled: sc.host.showGrid
        onActivated: sc.host.shuffle()
    }
    PickButton {
        objectName: "wall-looks"
        label: I18n.tr("mod-wallpaper.favourites")
        selected: sc.host.onlyLooks
        onActivated: sc.host.onlyLooks = !sc.host.onlyLooks
    }
}
