import QtQuick
import qs.core
import qs.components

// The wallpaper mod's picker for the appearance menu's Wallpaper pane (W84, docs/ux/appearance-menu.md "Panes"; W99):
// PickerCore (the documents, the paging, the actions, the keys — the same as the mod's own card, Panel.qml) laid out
// for the pane: the sources (Local, and Wallhaven while it is on) and the targets, Local's folders — shown, added,
// removed, one picked to browse — and the breadcrumb under it, search and sort, the grid (its columns follow the width,
// about 220 px each and at least four; its height is what the pane has left), the selected picture beside the grid
// when the pane is wide (the menu's live preview stands aside then) or its notes and actions under it, and the rotation
// row. The menu loads it beside this mod's Panel.qml (the `mods` document's file for `panel:wallpaper`), so it exists
// only while the mod is on and the pane is shown. The folders and rotation are this mod's settings, applied at once
// (they are not appearance: the menu's preview session is for the look); a picture is set at once (an action).
PickerCore {
    id: picker
    property var menu: null           // the appearance menu (its pane's height; its host decides nothing here)
    property string output: ""        // the output the menu was asked on
    // The height the pane shows at once: the grid takes what the rest leaves, so the pictures fill the view.
    readonly property real availH: menu && menu.paneHeight !== undefined && menu.paneHeight > 0 ? menu.paneHeight : 480
    readonly property bool wide: width >= 860
    // While the picker shows the selected picture beside its grid, the menu's live preview stands aside (I538: the
    // room is the pictures').
    readonly property bool ownsPreview: wide && onLibrary
    implicitHeight: col.implicitHeight

    // What the menu's live preview shows: the selected picture, and its colours while the theme goes with it.
    readonly property string previewPath: onLibrary && selectedRow && selectedRow.path && selectedRow.error === undefined
        ? selectedRow.path : ""
    readonly property var previewRoles: withTheme && previewCurrent && themePreview.roles ? themePreview.roles : null

    view: library.grid
    onWantsSearch: { search.input.forceActiveFocus(); search.input.selectAll() }
    onWantsFolderRow: if (!(crumbs.visible && crumbs.focusCurrent())) folderRow.focusCurrent()

    // The rows around the grid, summed (not the column's own height: that holds the grid, whose height is this).
    function chromeH() {
        var h = 0, n = 0
        for (var i = 0; i < col.children.length; i++) {
            var c = col.children[i]
            if (c === body || c === whLoader || !c.visible) continue
            h += c.height
            n++
        }
        return h + n * col.spacing
    }
    // (less the pane's scroll edge, which fades its last 24 px: the rotation row stays clear of it)
    readonly property real bodyH: Math.max(Math.round(library.cellH * 1.25), availH - chromeH() - 28)

    Column {
        id: col
        width: picker.width
        spacing: Theme.gap

        // the sources: Local, Wallhaven (while it is on); the count; the targets
        Item {
            width: parent.width
            height: Math.max(sources.height, targets.visible ? targets.height : 0)
            Row {
                id: sources
                spacing: Theme.xs
                Accessible.role: Accessible.PageTabList
                PickButton {
                    objectName: "wall-source-local"
                    label: I18n.tr("appearance-menu.wallpaper.local")
                    selected: picker.onLibrary
                    Accessible.role: Accessible.PageTab
                    onActivated: picker.tab = "library"
                }
                PickButton {
                    objectName: "wall-source-wallhaven"
                    visible: picker.wallhavenOn
                    label: I18n.tr("mod-wallpaper.tab.wallhaven")
                    selected: picker.tab === "wallhaven"
                    Accessible.role: Accessible.PageTab
                    onActivated: picker.tab = "wallhaven"
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: Theme.gap
                    color: picker.backendUp || !picker.loaded ? Theme.dim : Theme.error
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: !picker.loaded ? I18n.tr("mod-wallpaper.loading")
                        : (!picker.installed ? I18n.tr(picker.backend.reason || "mod-wallpaper.backend.missing")
                        : (picker.backendUp ? picker.tr2("appearance-menu.wallpaper.count", { n: picker.libraryCount })
                        : I18n.tr(picker.backend.reason || "mod-wallpaper.backend.down")))
                }
            }
            Targets {
                id: targets
                host: picker
                anchors.left: sources.right
                anchors.right: parent.right
                anchors.leftMargin: Theme.pad
            }
        }

        // ---- Local ----
        FolderChips {
            id: folderRow
            host: picker
            visible: picker.onLibrary
            width: parent.width
        }
        Crumbs {
            id: crumbs
            host: picker
            visible: picker.onLibrary && model.length > 0
            width: parent.width
        }
        Flow {
            id: toolbar
            visible: picker.onLibrary && picker.loaded && picker.installed && picker.libraryCount > 0
            width: parent.width
            spacing: Theme.xs
            SearchBox {
                id: search
                objectName: "wall-search"
                width: picker.wide ? Math.min(420, Math.round(toolbar.width * 0.4)) : Math.max(160, toolbar.width - sort.implicitW - toolbar.spacing)
                placeholder: I18n.tr("mod-wallpaper.search")
                liveMs: 250
                onEdited: t => picker.query = t
                onSubmitted: picker.focusGrid()
                onDown: picker.focusGrid()
            }
            SortChips {
                id: sort
                host: picker
                // the four chips' width, so they sit beside the field while they fit
                readonly property real implicitW: 340
                width: toolbar.width - search.width - toolbar.spacing >= implicitW ? toolbar.width - search.width - toolbar.spacing : toolbar.width
                height: Theme.controlH
            }
        }

        // the grid (or the state in its place), and the selected picture beside it on a wide pane
        Item {
            id: body
            visible: picker.onLibrary
            width: parent.width
            height: picker.bodyH
            readonly property real sideW: picker.wide ? Math.round(Math.min(360, Math.max(280, width * 0.3))) : 0
            LibraryGrid {
                id: library
                host: picker
                least: 4
                tabTo: picker.wide ? sidePreview.firstAction : underPreview.firstAction
                backTo: search.input
                width: parent.width - (picker.wide ? body.sideW + Theme.pad : 0)
                height: parent.height
            }
            Flickable {
                id: sideFlick
                visible: picker.wide && picker.showGrid && picker.selectedRow !== null
                x: parent.width - body.sideW
                width: body.sideW
                height: parent.height
                contentHeight: sidePreview.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height + 1
                PreviewPane {
                    id: sidePreview
                    host: picker
                    side: true
                    fitHeight: sideFlick.height
                    width: sideFlick.width
                }
            }
        }
        // a narrow pane: the selected picture's notes and the actions under the grid (the live preview shows it)
        PreviewPane {
            id: underPreview
            host: picker
            visible: !picker.wide && picker.onLibrary && picker.showGrid && picker.selectedRow !== null
            showImage: false
            showDiff: false
            width: parent.width
        }
        RotationRow {
            host: picker
            visible: picker.onLibrary
            width: parent.width
        }

        // ---- Wallhaven: the mod's own tab, made only while chosen ----
        Loader {
            id: whLoader
            active: picker.tab === "wallhaven"
            visible: active
            width: parent.width
            height: active ? Math.max(380, picker.availH - picker.chromeH() - 28) : 0
            sourceComponent: Component { Wallhaven { host: picker } }
        }

        Text {
            visible: text !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.error
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: picker.problemText()
        }
    }
}
