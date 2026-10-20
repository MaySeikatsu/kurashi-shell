import QtQuick
import qs.core
import qs.components

// The picker's Wallhaven tab (K48 (3), docs/ux/wallpaper.md "Wallhaven"; shellseikatsu `Services/WallhavenService.qml`).
// A view: `wallpaper.wallhaven.search` asks the daemon for one page (it fetches the API and the page's small thumbnails
// into its cache and answers with local files), `wallpaper.wallhaven.download` fetches one picture into the mod's data
// folder, then the picker's own `wallpaper.set` applies it (with the theme when the picker's theme switch is on).
// Ma: nothing is fetched until the tab opens; this item exists only while the tab is shown (the picker's Loader).
// States: searching, results, no results, offline, refused (a bad key, rate limited, Wallhaven off), downloading.
// Keys: / or Tab to the search field, Return searches; arrows move in the grid, Return sets, PageDown/PageUp page.
Item {
    id: wh
    required property var host

    property string query: ""
    property string sorting: "toplist"      // toplist | date_added | random | views | favorites | relevance
    property bool general: true
    property bool anime: true
    property bool people: true
    property bool sketchy: false            // SFW only by default; Sketchy is opt-in per search; NSFW is not offered
    property int page: 1
    property int lastPage: 1
    property int total: 0
    property string seed: ""                // random sorting: the daemon's seed keeps the pages stable
    property var rows: []
    property bool busy: false
    property bool searched: false
    property string errorKey: ""
    property string downloading: ""         // the id being downloaded
    property int token: 0
    property var gate: ({ open: true })
    readonly property var selected: grid.currentIndex >= 0 && grid.currentIndex < rows.length ? rows[grid.currentIndex] : null

    function categories() { return (general ? "1" : "0") + (anime ? "1" : "0") + (people ? "1" : "0") }
    function purity() { return sketchy ? "110" : "100" }
    function sizeText(bytes) {
        return bytes < 1048576 ? Math.round(bytes / 1024) + " KiB" : (bytes / 1048576).toFixed(1) + " MiB"
    }

    function search(toPage) {
        var g = gate
        var t = ++token
        busy = true
        errorKey = ""
        var args = { query: query, sorting: sorting, categories: categories(), purity: purity(), page: toPage || 1 }
        if (sorting === "random" && seed !== "" && (toPage || 1) > 1) args.seed = seed
        Store.act("wallpaper.wallhaven.search", args, function (done, err) {
            if (!g.open || t !== wh.token) return
            wh.busy = false
            wh.searched = true
            if (err) { wh.errorKey = err.msg || "mod-wallpaper.wallhaven.error.failed"; return }
            var d = (done && done.data) || {}
            wh.rows = d.rows || []
            wh.page = d.page || 1
            wh.lastPage = d.last_page || 1
            wh.total = d.total || 0
            wh.seed = d.seed || ""
            grid.currentIndex = 0
            if (wh.rows.length > 0 && !field.activeFocus) grid.forceActiveFocus()
        })
    }
    function apply(row, origin) {
        if (!row || downloading !== "") return
        if (!host.backendUp) { errorKey = "mod-wallpaper.backend.down"; return }
        var g = gate
        downloading = row.id
        errorKey = ""
        Store.act("wallpaper.wallhaven.download", { id: row.id }, function (done, err) {
            if (!g.open) return
            wh.downloading = ""
            if (err) { wh.errorKey = err.msg || "mod-wallpaper.wallhaven.error.failed"; return }
            var d = (done && done.data) || {}
            // The tile says it is saved now; the model is replaced, so the selection is put back.
            var at = grid.currentIndex, copy = wh.rows.slice()
            for (var i = 0; i < copy.length; i++)
                if (copy[i].id === row.id) copy[i] = Object.assign({}, copy[i], { local: d.path })
            wh.rows = copy
            grid.currentIndex = at
            if (d.path) host.setWallpaper(d.path, false, host.withTheme, origin)
        })
    }
    Component.onCompleted: { search(1); Qt.callLater(function () { if (wh.gate.open) field.forceActiveFocus() }) }
    Component.onDestruction: gate.open = false
    onSortingChanged: if (searched) search(1)
    onSketchyChanged: if (searched) search(1)
    onGeneralChanged: if (searched) search(1)
    onAnimeChanged: if (searched) search(1)
    onPeopleChanged: if (searched) search(1)

    // ---- toolbar: search, sorting ------------------------------------------------------------
    Row {
        id: bar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.xs
        Rectangle {
            width: Math.max(96, parent.width - sortTop.width - sortNew.width - sortRandom.width - parent.spacing * 3)
            height: Theme.controlH
            radius: Theme.rSm
            color: Theme.containerHigh
            border.width: field.activeFocus ? 1 : 0
            border.color: Theme.focusRing
            TextInput {
                id: field
                anchors.fill: parent
                anchors.leftMargin: Theme.gap
                anchors.rightMargin: Theme.gap
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Theme.fg
                selectionColor: Theme.accent
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                activeFocusOnTab: true
                maximumLength: 200
                onAccepted: { wh.query = text.trim(); wh.search(1) }
                Keys.onEscapePressed: event => { if (text !== "") { text = ""; event.accepted = true } else event.accepted = false }
                Keys.onDownPressed: if (wh.rows.length > 0) grid.forceActiveFocus()
                Accessible.role: Accessible.EditableText
                Accessible.name: I18n.tr("mod-wallpaper.wallhaven.search")
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: field.text.length === 0
                    text: I18n.tr("mod-wallpaper.wallhaven.search")
                    color: Theme.dim
                    font: field.font
                }
            }
        }
        PickButton {
            id: sortTop
            label: I18n.tr("mod-wallpaper.wallhaven.sort.toplist")
            selected: wh.sorting === "toplist"
            onActivated: wh.sorting = "toplist"
        }
        PickButton {
            id: sortNew
            label: I18n.tr("mod-wallpaper.wallhaven.sort.date_added")
            selected: wh.sorting === "date_added"
            onActivated: wh.sorting = "date_added"
        }
        PickButton {
            id: sortRandom
            label: I18n.tr("mod-wallpaper.wallhaven.sort.random")
            selected: wh.sorting === "random"
            onActivated: { if (wh.sorting === "random") wh.search(1); else wh.sorting = "random" }
        }
    }

    // ---- filters: categories and purity (SFW is always in; Sketchy is a choice) ---------------------------------------
    Flow {
        id: filters
        anchors.top: bar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.xs
        spacing: Theme.xs
        PickButton {
            label: I18n.tr("mod-wallpaper.wallhaven.category.general")
            selected: wh.general
            // At least one category stays on: Wallhaven treats none as all.
            onActivated: if (!wh.general || wh.anime || wh.people) wh.general = !wh.general
        }
        PickButton {
            label: I18n.tr("mod-wallpaper.wallhaven.category.anime")
            selected: wh.anime
            onActivated: if (!wh.anime || wh.general || wh.people) wh.anime = !wh.anime
        }
        PickButton {
            label: I18n.tr("mod-wallpaper.wallhaven.category.people")
            selected: wh.people
            onActivated: if (!wh.people || wh.general || wh.anime) wh.people = !wh.people
        }
        Item { width: Theme.gap; height: 1 }
        PickButton {
            label: I18n.tr("mod-wallpaper.wallhaven.purity.sfw")
            selected: true
            enabled: false
            Accessible.description: I18n.tr("mod-wallpaper.wallhaven.purity.sfw.always")
        }
        PickButton {
            label: I18n.tr("mod-wallpaper.wallhaven.purity.sketchy")
            selected: wh.sketchy
            onActivated: wh.sketchy = !wh.sketchy
        }
    }

    // ---- the action bar: the selection, paging, Set -----------------------------------------------------------------
    Item {
        id: actions
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.controlH + Theme.shadowDy
        visible: wh.rows.length > 0
        Text {
            anchors.left: parent.left
            anchors.right: pager.left
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: {
                var r = wh.selected
                if (!r) return ""
                var parts = [r.resolution || ""]
                if (r.file_size) parts.push(wh.sizeText(r.file_size))
                if (r.category) parts.push(I18n.tr("mod-wallpaper.wallhaven.category." + r.category))
                if (r.local) parts.push(I18n.tr("mod-wallpaper.wallhaven.saved"))
                return parts.join(" · ")
            }
        }
        Row {
            id: pager
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.xs
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "chevron_left"
                glyph: "‹"
                a11y: I18n.tr("mod-wallpaper.wallhaven.page.prev")
                enabled: !wh.busy && wh.page > 1
                onClicked: wh.search(wh.page - 1)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.features: { "tnum": 1 }
                font.family: Theme.fam(text, Theme.families)
                text: wh.page + " / " + wh.lastPage
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "chevron_right"
                glyph: "›"
                a11y: I18n.tr("mod-wallpaper.wallhaven.page.next")
                enabled: !wh.busy && wh.page < wh.lastPage
                onClicked: wh.search(wh.page + 1)
            }
            Button {
                anchors.verticalCenter: parent.verticalCenter
                primary: true
                label: wh.downloading !== "" ? I18n.tr("mod-wallpaper.wallhaven.downloading")
                    : I18n.tr(host.withTheme ? "mod-wallpaper.wallhaven.set.theme" : "mod-wallpaper.wallhaven.set")
                enabled: wh.selected !== null && wh.downloading === "" && host.backendUp
                onClicked: wh.apply(wh.selected, null)
            }
        }
    }

    // ---- body: the grid, or the state that replaces it --------------------------------------------------------------
    Item {
        id: body
        anchors.top: filters.bottom
        anchors.bottom: actions.visible ? actions.top : parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.gap
        anchors.bottomMargin: Theme.gap
        clip: true

        Column {
            visible: wh.rows.length === 0 || (wh.busy && !wh.searched)
            anchors.centerIn: parent
            width: parent.width - Theme.pad * 2
            spacing: Theme.gap
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                color: wh.errorKey !== "" ? Theme.error : Theme.fg
                font.pixelSize: Theme.fsTitle
                font.family: Theme.fam(text, Theme.families)
                text: wh.busy ? I18n.tr("mod-wallpaper.wallhaven.searching")
                    : wh.errorKey !== "" ? I18n.tr(wh.errorKey)
                    : wh.searched ? I18n.tr("mod-wallpaper.wallhaven.empty.title") : ""
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                color: Theme.dim
                font.pixelSize: Theme.fsLabel
                font.family: Theme.fam(text, Theme.families)
                visible: text !== ""
                text: wh.busy ? ""
                    : wh.errorKey !== "" ? (wh.errorKey.indexOf("mod-wallpaper.wallhaven.error.") === 0 ? I18n.tr(wh.errorKey + ".hint") : "")
                    : wh.searched ? I18n.tr("mod-wallpaper.wallhaven.empty.hint") : ""
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !wh.busy && wh.errorKey !== ""
                label: I18n.tr("mod-wallpaper.wallhaven.retry")
                onClicked: wh.search(wh.page)
            }
        }

        GridView {
            id: grid
            anchors.fill: parent
            visible: wh.rows.length > 0
            opacity: wh.busy ? 0.5 : 1
            clip: true
            keyNavigationEnabled: true
            activeFocusOnTab: true
            model: wh.rows
            readonly property int columns: Math.max(2, Math.floor(width / 160))
            cellWidth: Math.floor(width / columns)
            cellHeight: Math.round((cellWidth - 8) * 2 / 3) + 8
            boundsBehavior: Flickable.StopAtBounds
            Accessible.role: Accessible.List
            Accessible.name: I18n.tr("mod-wallpaper.wallhaven.title")
            Keys.onReturnPressed: wh.apply(wh.selected, null)
            Keys.onEnterPressed: wh.apply(wh.selected, null)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_PageDown && wh.page < wh.lastPage) { wh.search(wh.page + 1); event.accepted = true }
                else if (event.key === Qt.Key_PageUp && wh.page > 1) { wh.search(wh.page - 1); event.accepted = true }
                else if (event.key === Qt.Key_Slash) { field.forceActiveFocus(); event.accepted = true }
            }
            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                readonly property bool current: GridView.isCurrentItem
                width: grid.cellWidth
                height: grid.cellHeight
                Accessible.role: Accessible.ListItem
                Accessible.name: (modelData.resolution || "") + (modelData.local ? ", " + I18n.tr("mod-wallpaper.wallhaven.saved") : "")
                Rectangle {
                    id: tile
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: Theme.rSm
                    color: Theme.containerHigh
                    border.width: cell.current ? 2 : 0
                    border.color: Theme.accent
                    clip: true
                    Image {
                        id: thumb
                        anchors.fill: parent
                        anchors.margins: tile.border.width
                        source: cell.modelData.thumb ? host.fileUrl(cell.modelData.thumb) : ""
                        sourceSize: Qt.size(320, 214)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status === Image.Ready
                    }
                    // A tile whose thumbnail did not come: its main colour, if Wallhaven named one, and a mark.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: tile.border.width
                        visible: thumb.status !== Image.Ready
                        color: (cell.modelData.colors && cell.modelData.colors.length > 0) ? cell.modelData.colors[0] : "transparent"
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: thumb.status !== Image.Ready
                        color: Theme.dim
                        font.pixelSize: Theme.fsTitle
                        text: cell.modelData.thumb_error ? "!" : "…"
                    }
                    Row {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 4
                        spacing: 3
                        Chip {
                            visible: cell.modelData.local !== undefined && cell.modelData.local !== ""
                            text: "✓"
                            fg: Theme.accent
                            bg: Theme.surfaceAlpha
                            edge: Theme.accent
                        }
                        Chip {
                            visible: cell.modelData.purity === "sketchy"
                            text: I18n.tr("mod-wallpaper.wallhaven.purity.sketchy")
                            fg: Theme.fg
                            bg: Theme.surfaceAlpha
                            edge: Theme.outline
                        }
                    }
                    Chip {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: 4
                        text: wh.downloading === cell.modelData.id ? I18n.tr("mod-wallpaper.wallhaven.downloading")
                            : (cell.modelData.resolution || "")
                        fg: Theme.fg
                        bg: Theme.surfaceAlpha
                        edge: Theme.outline
                    }
                    FocusRing { anchors.fill: parent; corner: tile.radius; shown: grid.activeFocus && cell.current }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { grid.currentIndex = cell.index; grid.forceActiveFocus() }
                        onDoubleClicked: { grid.currentIndex = cell.index; wh.apply(cell.modelData, host.originOf(tile)) }
                    }
                }
            }
        }
    }
}
