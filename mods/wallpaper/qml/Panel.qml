import QtQuick
import qs.core
import qs.components

// The wallpaper picker (Stage panel `mod:wallpaper:wallpaper`, docs/ux/wallpaper.md). PickerCore (the documents, the
// paging, the actions, the keys) laid out for a card: the header (backend, rotation, count; the overflow), the tabs and
// the targets, the folders and the breadcrumb, search and sort, then the grid with the selected picture beside it (a
// wide card) or under it, and the rotation row. It fills the Stage card: no frame of its own, the card is the frame.
// Two tabs (K48 (3)): the library, and Wallhaven (Wallhaven.qml, made only while its tab is shown; it fetches nothing
// before that). The targets, the theme switch and Apply's `wallpaper.set` are shared by both. Keys: PickerCore.gridKey.
PickerCore {
    id: picker
    // The card asks for the widest card (contract row 66, `cardWidth`, 360..720 px): 3-4 thumbnail columns at 640-720.
    // The Stage gives the content width (the card minus 2 x 16 px), so this is the width the picker lays out for.
    property int cardWidth: 720
    implicitWidth: cardWidth - 2 * (Theme.pad + 4)
    // I538, I606: the picker wants room for its pictures: a large card (the Stage hands its height as `fillHeight`); in
    // a sidebar it takes the height on offer as before.
    readonly property bool cardLarge: true
    property real fillHeight: 0
    implicitHeight: fillHeight > 0 ? fillHeight : 640
    // A wide picker shows the selected picture beside the grid (the grid keeps the height), a narrow one under it.
    readonly property bool wide: width >= 860
    property bool menuOpen: false       // the header's overflow (the cache, the Settings page), open

    view: library.grid
    onWantsSearch: { search.input.forceActiveFocus(); search.input.selectAll() }
    onWantsFolderRow: if (!(crumbs.visible && crumbs.focusCurrent())) folderRow.focusCurrent()
    // The Stage card takes the keyboard when the panel opens, and queues that before the panel exists; the picker
    // asks for its grid after it, so the arrows reach the grid. Escape still reaches the card (keys propagate up).
    Component.onCompleted: later(focusGrid)
    onShowGridChanged: if (showGrid && !search.input.activeFocus) later(focusGrid)

    // The overflow menu: opened from its button (focus goes to its first item), closed by Escape, a click outside, or
    // the item; closing returns the focus to the button.
    function toggleMenu() { if (menuOpen) closeMenu(); else openMenu() }
    function openMenu() {
        menuOpen = true
        later(function () { clearItem.forceActiveFocus() })
    }
    function closeMenu() {
        menuOpen = false
        moreButton.forceActiveFocus()
    }

    // ---- header: the backend, the rotation and the count in one line; the overflow at its end -------------------
    Text {
        id: title
        anchors.top: parent.top
        anchors.left: parent.left
        text: I18n.tr("mod-wallpaper.title")
        color: Theme.fg
        font.pixelSize: Theme.fsTitle
        font.family: Theme.fam(text, Theme.families)
    }
    Text {
        id: status
        anchors.baseline: title.baseline
        anchors.left: title.right
        anchors.right: moreButton.left
        anchors.leftMargin: Theme.gap
        anchors.rightMargin: Theme.gap
        elide: Text.ElideRight
        color: picker.backendUp || !picker.loaded ? Theme.dim : Theme.error
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: picker.statusText()
    }
    // Maintenance is not in the main view (I83): the thumbnail cache, what clearing it frees, and the mod's Settings page.
    IconButton {
        id: moreButton
        anchors.top: parent.top
        anchors.right: parent.right
        glyph: "…"
        a11y: I18n.tr("mod-wallpaper.more")
        onClicked: picker.toggleMenu()
    }
    // Clicks outside the open menu close it (the menu sits above this catcher).
    MouseArea {
        anchors.fill: parent
        z: 10
        visible: picker.menuOpen
        onClicked: picker.closeMenu()
    }
    Rectangle {
        id: cacheMenu
        z: 11
        visible: picker.menuOpen
        anchors.top: moreButton.bottom
        anchors.right: parent.right
        anchors.topMargin: Theme.xs
        width: Math.min(parent.width, 240)
        height: menuCol.implicitHeight + 2 * Theme.gap
        radius: Theme.rSm
        color: Theme.containerHigh
        border.width: 1
        border.color: Theme.outline
        Keys.onEscapePressed: picker.closeMenu()
        Column {
            id: menuCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.gap
            spacing: Theme.xs
            Button {
                id: clearItem
                width: parent.width
                label: I18n.tr("mod-wallpaper.cache.clear")
                onClicked: { picker.closeMenu(); picker.clearCache() }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                visible: picker.cacheBytes >= 0
                text: picker.tr2("mod-wallpaper.cache.size", { size: picker.sizeText(picker.cacheBytes) })
            }
            // The mod's whole Settings page (I40: `settings.open {page}`), for what the picker does not show: fit,
            // transitions, the backend.
            Button {
                objectName: "wallpaper-settings"
                width: parent.width
                label: I18n.tr("mod-wallpaper.settings")
                onClicked: {
                    picker.closeMenu()
                    Store.act("settings.open", { page: "mod:wallpaper" })
                }
            }
        }
    }

    // ---- tabs (the library, Wallhaven) and the targets beside them ---------------------------------------------
    Row {
        id: tabs
        // one source alone needs no tabs (Wallhaven off)
        visible: picker.wallhavenOn
        anchors.top: title.bottom
        anchors.left: parent.left
        anchors.topMargin: Theme.gap
        spacing: Theme.xs
        Accessible.role: Accessible.PageTabList
        PickButton {
            objectName: "wall-tab-library"
            label: I18n.tr("mod-wallpaper.tab.library")
            selected: picker.onLibrary
            Accessible.role: Accessible.PageTab
            onActivated: { picker.tab = "library"; picker.later(picker.focusGrid) }
        }
        PickButton {
            objectName: "wall-tab-wallhaven"
            visible: picker.wallhavenOn
            label: I18n.tr("mod-wallpaper.tab.wallhaven")
            selected: picker.tab === "wallhaven"
            Accessible.role: Accessible.PageTab
            onActivated: picker.tab = "wallhaven"
        }
    }
    Targets {
        id: targets
        host: picker
        anchors.top: tabs.top
        anchors.left: tabs.visible ? tabs.right : parent.left
        anchors.right: parent.right
        anchors.leftMargin: tabs.visible ? Theme.pad : 0
    }
    readonly property real topBottom: Math.max(title.y + title.height, tabs.visible ? tabs.y + tabs.height : 0,
        targets.visible ? targets.y + targets.height : 0)

    // ---- the library: folders, the breadcrumb, search and sort -------------------------------------------------
    Column {
        id: libraryHead
        visible: picker.onLibrary
        y: picker.topBottom + Theme.gap
        width: parent.width
        spacing: Theme.xs
        FolderChips {
            id: folderRow
            host: picker
            width: parent.width
        }
        Crumbs {
            id: crumbs
            host: picker
            width: parent.width
        }
        Flow {
            id: toolbar
            width: parent.width
            spacing: Theme.xs
            SearchBox {
                id: search
                width: picker.wide ? Math.min(420, Math.round(toolbar.width * 0.4)) : toolbar.width
                placeholder: I18n.tr("mod-wallpaper.search")
                liveMs: 250
                onEdited: t => picker.query = t
                onSubmitted: picker.focusGrid()
                onDown: picker.focusGrid()
                onCleared: picker.focusGrid()
            }
            SortChips {
                host: picker
                width: picker.wide ? toolbar.width - search.width - toolbar.spacing : toolbar.width
                height: Theme.controlH
            }
        }
    }

    // ---- footer: what went wrong, the rotation, a restart while the backend is down ------------------------------
    Column {
        id: footer
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.xs
        Text {
            width: parent.width
            visible: text !== ""
            elide: Text.ElideRight
            color: Theme.error
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: picker.problemText()
        }
        Item {
            width: parent.width
            height: Math.max(rotationRow.height, restartButton.visible ? restartButton.height : 0)
            RotationRow {
                id: rotationRow
                host: picker
                anchors.left: parent.left
                anchors.right: restartButton.visible ? restartButton.left : parent.right
                anchors.rightMargin: Theme.gap
            }
            Button {
                id: restartButton
                anchors.right: parent.right
                label: I18n.tr("mod-wallpaper.backend.restart")
                // (the empty state has its own while the grid is not shown)
                visible: picker.installed && picker.loaded && !picker.backendUp && picker.showGrid
                onClicked: picker.restartBackend()
            }
        }
    }

    // ---- the Wallhaven tab: between the targets and the footer, made only while shown --------------------------
    Loader {
        id: wallhaven
        active: picker.tab === "wallhaven"
        visible: active
        y: picker.topBottom + Theme.gap
        width: parent.width
        height: footer.y - Theme.gap - y
        sourceComponent: Component { Wallhaven { host: picker } }
    }

    // ---- body: the grid, and the selected picture beside it (wide) or under it ---------------------------------------
    Item {
        id: body
        visible: picker.onLibrary
        y: libraryHead.y + libraryHead.height + Theme.gap
        width: parent.width
        height: footer.y - Theme.gap - y
        readonly property bool previewShown: picker.showGrid && picker.selectedRow !== null
        readonly property real sideW: picker.wide ? Math.round(Math.min(380, Math.max(280, width * 0.28))) : 0

        LibraryGrid {
            id: library
            host: picker
            least: 2
            tabTo: preview.firstAction
            width: picker.wide ? parent.width - body.sideW - Theme.pad : parent.width
            height: picker.wide || !body.previewShown ? parent.height : parent.height - sideFlick.height - Theme.gap
        }
        // A hairline between the grid and the selected picture; the card stays the only frame.
        Rectangle {
            visible: body.previewShown
            x: picker.wide ? library.width + Theme.pad / 2 : 0
            y: picker.wide ? 0 : library.height + Theme.gap / 2
            width: picker.wide ? 1 : parent.width
            height: picker.wide ? parent.height : 1
            color: Theme.outline
            opacity: 0.5
        }
        Flickable {
            id: sideFlick
            visible: body.previewShown
            x: picker.wide ? parent.width - body.sideW : 0
            y: picker.wide ? 0 : parent.height - height
            width: picker.wide ? body.sideW : parent.width
            height: picker.wide ? parent.height : Math.min(preview.implicitHeight, parent.height * 0.5)
            contentHeight: preview.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height + 1
            PreviewPane {
                id: preview
                host: picker
                side: picker.wide
                fitHeight: picker.wide ? sideFlick.height : 0
                // a narrow, short card (a large card on a small screen): the name and the actions, the grid keeps rows
                showImage: picker.wide || body.height >= 460
                showDiff: picker.wide || body.height >= 400
                width: sideFlick.width
            }
        }
        // a short column (the picture at its least) scrolls: what it cuts blends out, as the grid's does
        ScrollEdge { view: sideFlick }
    }
}
