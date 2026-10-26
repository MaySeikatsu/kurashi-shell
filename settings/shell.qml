import QtQuick
import Quickshell
import Quickshell.Io
import "core"
import "components"
import "pages"

// Settings app (K2): a separate, on-demand process; `qs -p settings`. Pages are generated from the daemon's
// `schema.settings` document (rule 3); this file lays out the chrome. `settings.window` (K63) picks the host: `window`, a
// normal xdg toplevel the compositor places and tiles, or `sheet`, a layer surface the app draws over the focused output
// (components/SheetHost.qml). The app's content is one item (`win`) that either host holds; switching the key while open
// moves that same item into the other host, so the page, the scroll position, the search and an open preview stay. No
// host maps before the config has arrived (a sheet must not flash up as a window first); without a daemon the window
// comes after a moment, with the disconnected veil. The process ends when the window closes or the sheet is dismissed.
// `KURASHI_SETTINGS_KEY=<key> qs -p settings` opens that setting's row at start; a running app takes the same link
// through `qs -p settings ipc call settings jump <key>`; `kurashi settings <key>` and the daemon action `settings.open
// {key}` do either for you (K32). A page link (I40, K65) works the same way: `KURASHI_SETTINGS_PAGE=<page>` at start,
// `ipc call settings page <page>` while open, `settings.open {page}` for either; `<page>` is a schema page id (`keys`) or
// `mod:<id>` for a mod's page.
ShellRoot {
    id: root
    readonly property bool configIn: Store.config.values !== undefined
    property bool waited: false
    Timer {
        interval: 1500
        running: !root.configIn && !root.waited
        onTriggered: root.waited = true
    }
    // "" until the config is in (or the daemon did not answer in time); then the key's value, live.
    readonly property string host: root.configIn ? (Store.valueOf("settings.window") === "sheet" ? "sheet" : "window")
        : (root.waited ? "window" : "")

    // Closing ends an open preview: the value it started from comes back, as Esc would do.
    property var sheetHost: null
    function quit(): void { Changes.putBack(); Qt.quit() }
    // A host takes the content: the item moves into it with its state; the keyboard focus goes where it was (else to the
    // list, where typing starts a search).
    // The relief is made anew in each host (Theme.hosted): a Relief reads its layer window once it is in one, and a moved
    // item would keep the window it left (its tiles, place and output).
    function adopt(slot: Item): void {
        const had = win.Window.activeFocusItem
        Theme.hosted = false
        win.parent = slot
        Qt.callLater(function () {
            Theme.hosted = true
            if (had && root.inside(had)) had.forceActiveFocus()
            else keys.forceActiveFocus()
        })
    }
    // The sheet's corners, which the content draws itself (header, sidebar, ground); square in a window.
    readonly property real cornerR: root.host === "sheet" && root.sheetHost ? root.sheetHost.radius : 0
    function release(slot: Item): void { if (win.parent === slot) win.parent = null }
    function inside(item: Item): bool {
        for (var it = item; it; it = it.parent) if (it === win) return true
        return false
    }

    LazyLoader {
        active: root.host === "window"
        FloatingWindow {
            title: I18n.tr("settings.ui.title")
            implicitWidth: 1040
            implicitHeight: 740
            minimumSize: Qt.size(640, 420)
            color: Theme.surface
            // The material (K63): a window is not on the shell's continuous sheet (it has no place on the output the
            // shell knows), so its relief is a sheet of its own from its top-left corner (Light.originOf gives a window
            // without layer anchors the origin 0,0). One tile set for every Relief in it; the pointer lamp over it.
            property var tileSheet: windowTiles.item
            Loader {
                id: windowTiles
                active: Theme.texShell && Theme.texTilePx > 0
                sourceComponent: TileSheet {}
            }
            LightSense {}
            Component.onCompleted: root.adopt(contentItem)
            Component.onDestruction: root.release(contentItem)
            // Closed by the compositor or the user; a re-host to the sheet (host changed first) does not end the app.
            onVisibleChanged: if (!visible && root.host === "window") root.quit()
        }
    }
    LazyLoader {
        active: root.host === "sheet"
        SheetHost {
            id: sheet
            Component.onCompleted: { root.sheetHost = sheet; root.adopt(sheet.slot) }
            Component.onDestruction: { if (root.sheetHost === sheet) root.sheetHost = null; root.release(sheet.slot) }
            onDismissed: root.quit()
        }
    }

    // The content both hosts show (one instance; it has no window until a host adopts it).
    Item {
        id: win
        anchors.fill: parent
        readonly property bool sheet: root.host === "sheet"
        // Frames the host window has drawn (the settings test's idle check: none while open and still, Ma).
        property int frames: 0
        Connections {
            target: win.Window.window
            function onFrameSwapped() { win.frames++ }
        }
        // Esc that no control took (a field, a dropdown, a preview's put back take theirs first) dismisses the sheet; the
        // window is unchanged.
        Keys.onEscapePressed: event => {
            if (win.sheet) win.dismiss()
            else event.accepted = false
        }
        function dismiss(): void {
            Changes.putBack()
            if (root.sheetHost) root.sheetHost.close()
            else root.quit()
        }

        Shortcut {
            sequence: "Ctrl+F"
            onActivated: search.focusInput()
        }

        // "" = first schema page; "@changed", "@mods" and "@profiles" = the Changed view, the Mods and the profiles pages.
        property string page: ""
        property string query: ""
        property bool advanced: false
        property string output: ""
        readonly property var pages: Store.schema.pages || []
        readonly property string current: page !== "" ? page : (pages.length ? pages[0].id : "")
        readonly property bool searching: query.trim() !== ""
        readonly property bool special: current === "@changed" || current === "@mods" || current === "@profiles"
        // The sidebar: the core pages keep their order, and each mod's page sits among them by name, before the first core
        // page that sorts after it (K25). Then Changed, Mods and Profiles. `mod` is a mod's id, "" otherwise.
        readonly property var navItems: {
            var strings = I18n.strings   // re-evaluated when the strings arrive
            var entryOf = function (x) { return { id: x.id, label: x.label, mod: x.mod !== undefined ? x.mod : "" } }
            var nameOf = function (x) { return I18n.tr(x.label) }
            var core = win.pages.filter(function (x) { return x.mod === undefined }).map(entryOf)
            var mods = win.pages.filter(function (x) { return x.mod !== undefined }).map(entryOf)
            mods.sort(function (a, b) { return nameOf(a).localeCompare(nameOf(b)) })
            var out = []
            var m = 0
            core.forEach(function (c) {
                while (m < mods.length && nameOf(mods[m]).localeCompare(nameOf(c)) < 0) out.push(mods[m++])
                out.push(c)
            })
            while (m < mods.length) out.push(mods[m++])
            return out.concat([{ id: "@changed", label: "settings.ui.changed", mod: "" },
                               { id: "@mods", label: "settings.ui.mods", mod: "" },
                               { id: "@profiles", label: "settings.ui.profiles", mod: "" }])
        }
        readonly property int changedCount: Store.changedEntries().length

        // A search hit was chosen (Enter, or a breadcrumb): leave the search, open the row's page (an advanced row needs the
        // advanced view) and bring the row into view. From the keyboard the focus goes to the row's control as well.
        function jump(pageId: string, row: var, byKeyboard: bool): void {
            if (row.advanced) win.advanced = true
            win.query = ""
            win.page = pageId
            settingsPages.reveal(row.key, byKeyboard)
        }
        function jumpFirst(): void {
            if (!win.searching) return
            const h = settingsPages.firstHit()
            if (h) win.jump(h.pageId, h.row, true)
        }
        // A deep link: the row, on its page, in view. Unknown keys open nothing.
        function openKey(key: string): void {
            const h = Store.rowOf(key)
            if (h) win.jump(h.pageId, h.row, false)
        }
        // A page link (I40): `mod:<id>` names a mod's page (`mods.<id>` in the schema), anything else a page id. The page
        // opens at its top, out of a search; unknown pages open nothing (the daemon refuses them first).
        function pageIdOf(link: string): string {
            const id = link.indexOf("mod:") === 0 ? "mods." + link.slice(4) : link
            return win.pages.some(function (x) { return x.id === id }) ? id : ""
        }
        function openPage(link: string): bool {
            const id = win.pageIdOf(link)
            if (id === "") return false
            win.query = ""
            win.page = id
            settingsPages.pinKey = ""
            settingsPages.contentY = 0
            return true
        }
        // Leaving a page, searching or closing ends a preview (Changes): it is put back. A query the app cleared (a jump, a
        // page change) clears the field too, even while the field has the focus (its text follows the query only then).
        onPageChanged: Changes.putBack()
        onQueryChanged: {
            if (query !== "") Changes.putBack()
            else search.clear()
        }

        // A deep link given at start is opened once the schema has arrived and a host holds the content (the row's place is
        // only known once the page is laid out at the host's size).
        property bool startKeyDone: false
        readonly property string startKey: Quickshell.env("KURASHI_SETTINGS_KEY") || ""
        function openStartKey(): void {
            if (!win.startKeyDone && win.startKey !== "" && win.parent !== null && win.width > 0
                    && Store.rowOf(win.startKey)) {
                win.startKeyDone = true
                win.openKey(win.startKey)
            }
        }
        // The same for a page link given at start (a key, if both were given, wins: it names a page too).
        property bool startPageDone: false
        readonly property string startPage: Quickshell.env("KURASHI_SETTINGS_PAGE") || ""
        function openStartPage(): void {
            if (!win.startPageDone && win.startKey === "" && win.startPage !== "" && win.parent !== null && win.width > 0
                    && win.pageIdOf(win.startPage) !== "") {
                win.startPageDone = true
                win.openPage(win.startPage)
            }
        }
        onParentChanged: { openStartKey(); openStartPage() }
        onWidthChanged: { openStartKey(); openStartPage() }
        Connections {
            target: Store
            function onSchemaChanged() { win.openStartKey(); win.openStartPage() }
        }

        // Test/automation hook: `qs -p settings ipc call settings <fn> ...`. Goes through the same paths as the controls
        // (Store, Changes, page selection), so it exercises the real UI.
        IpcHandler {
            target: "settings"
            function goto(id: string): void { win.page = id; win.query = "" }
            function find(q: string): void { win.query = q }
            function set(key: string, json: string): void {
                Store.setValue(key, JSON.parse(json), win.output)
            }
            function output(name: string): void { win.output = name }
            // The page on screen: its id ("bar", "appearance", "@changed", …).
            function current(): string { return win.current }
            // Settings as a sheet (K63): the host in use — for the sheet its rectangle on the output, as
            // "sheet x,y WxH on <output> WxH" —, the page's scroll position, and the frames drawn so far (idle check).
            function host(): string {
                const h = root.sheetHost
                if (!h) return root.host
                const f = h.frame
                return "sheet " + f.x + "," + f.y + " " + f.width + "x" + f.height + " on "
                    + (h.screen ? h.screen.name : "?") + " " + h.width + "x" + h.height
            }
            function scrollY(): string { return "" + Math.round(settingsPages.contentY) }
            function scroll(y: int): void { settingsPages.pinKey = ""; settingsPages.contentY = y }
            function frames(): string { return "" + win.frames }
            // Start-up state for the deep link test: the key the environment named, and whether it was opened.
            function dbg(): string {
                return "startKey=" + win.startKey + ",done=" + win.startKeyDone + ",schemaPages=" + win.pages.length
                    + ",rowOf=" + (Store.rowOf(win.startKey) ? "yes" : "no")
                    + ",startPage=" + win.startPage + ",pageDone=" + win.startPageDone
            }
            function advanced(on: bool): void { win.advanced = on }
            function preview(name: string): void { win.page = "@profiles"; profiles.select(name) }
            function jump(key: string): void { win.openKey(key) }
            // A page link (I40): `keys`, `mod:<id>`; the daemon's `settings.open {page}` calls it on a running window.
            function page(link: string): void { win.openPage(link) }
            function mod(id: string, on: bool): void { modsPage.setEnabled(id, on) }
            function modLoad(id: string): void { modsPage.load(id) }
            function modUnload(id: string): void { modsPage.unload(id) }
            // Mod pages test (K25): the sidebar's entries in order, as ids; the core pages keep theirs.
            function navOrder(): string { return win.navItems.map(function (x) { return x.id }).join(",") }
            // Dropdown test (I9): opens the dropdown of a row on this page, as Enter does on its focus.
            function openChoice(key: string): void { settingsPages.openControl(key) }
            // Mods test (B8): the refusal line a row shows, empty when none is shown.
            function modRefusal(id: string): string { return modsPage.failures[id] ? modsPage.failures[id].text : "" }
            // Keyboard test: the control that has keyboard focus: its objectName, else its accessible name.
            function focused(): string {
                const f = keys.Window.activeFocusItem
                if (!f) return "(none)"
                return f.objectName || f.Accessible.name || ("(" + f.toString() + ")")
            }
            // Keyboard test: put focus back on the list, where Tab starts walking the window.
            function focusList(): void { keys.forceActiveFocus() }
            // History test (K27): the Undo/Redo state the header shows, and the same click as Undo's.
            function undoState(): string {
                return "undo=" + (Store.canUndo ? "on" : "off") + ",redo=" + (Store.redoShown ? "on" : "off")
            }
            function undo(): void { Store.undo() }
            // Profiles test: the names the Profiles page lists now.
            function profileNames(): string { return profiles.profiles.map(function (x) { return x.name }).join(",") }
            // Preview test (UX brief, settings 3): the open preview as "key=value" ("none" when there is none), and the same
            // Enter and Esc as the buttons.
            function previewState(): string {
                const s = Changes.session
                return s === null ? "none" : (s.key + "=" + JSON.stringify(s.shown))
            }
            function keep(): void { Changes.keep() }
            function putBack(): void { Changes.putBack() }
            // Changed view test: how many settings differ from the defaults.
            function changed(): string { return "" + win.changedCount }
            // Invalid input (UX brief, States): the refusal a row shows under its control, "" when none.
            function rowError(key: string): string { return Store.rowErrors[key] || "" }
            // Held-back values (I64 (3)): the user value a forced layer keeps out of effect, as JSON, or "none".
            function held(key: string): string { const h = Store.heldUserOf(key, ""); return h ? JSON.stringify(h.value) : "none" }
            // Section cards (K48 (5)): the cards the page shows, as "page.section", in order.
            function sections(): string { return settingsPages.cardNames().join(",") }
            // Theme export (K49): each app the status under the row lists, as name:state (written, included, missing,
            // error), "none" while the document is not there; and the copy result of an app ("copied", "error", "none").
            function exportState(): string {
                const d = Store.docs["svc.theme_export"]
                if (!d || !Array.isArray(d.targets)) return "none"
                return d.targets.map(function (t) {
                    return t.name + ":" + (t.error ? "error" : !t.include ? "written" : (t.include.present ? "included" : "missing"))
                }).join(",")
            }
            function exportCopied(name: string): string { return settingsPages.copyState(name) }
            // Keys (K64): the binds file as `state:include` (written:missing, written:included, managed, foreign,
            // unsupported, off, error; "none" before the document), one shortcut row as JSON (recording, a pending
            // Replace "combo>key", the notice, whether the compositor's shortcuts are inhibited, the lines under it), a
            // bind's state as the daemon says it, and the include line's copy result.
            function keysState(): string {
                const d = Store.docs["svc.keys"]
                if (!d || !d.state) return "none"
                return d.state + (d.state === "written" ? ":" + (d.include && d.include.present ? "included" : "missing") : "")
            }
            function keysRow(key: string): string { return settingsPages.keysRow(key) }
            function keyBind(key: string): string {
                const d = Store.docs["svc.keys"]
                const b = d && Array.isArray(d.binds) ? d.binds.find(function (x) { return x.key === key }) : null
                return b ? b.state + (b.config ? ":" + b.config : "") : "none"
            }
            function keysCopied(): string { return settingsPages.keysCopied() }
            // Appearance (W29, K53): a card picked (JSON value; a style or a look by its action), the category chips of a
            // row and the open one, a chip opened, the "differs from the style" line and its Reset, and a scroll to a
            // named item (a block, "block:<key>"; the line, "differs").
            function pick(key: string, json: string): void { settingsPages.pick(key, JSON.parse(json)) }
            function categories(key: string): string { return settingsPages.categories(key) }
            function openCategory(key: string): string { return settingsPages.openCategory(key) }
            function category(key: string, id: string): void { settingsPages.openCategoryOf(key, id) }
            function differs(): string { return settingsPages.differs() }
            function resetToStyle(): void { settingsPages.resetToStyle() }
            function scrollTo(name: string): void { settingsPages.scrollTo(name) }
            function appearance(): string { return JSON.stringify(Store.theme.appearance || null) }
            // The output picker's names (I241: no "*" alias), the edge Settings › Layout shows, and whether an item named so is on
            // the page (the layout screen's strips, radio and selectors).
            function outputs(): string { return Store.outputNames().join(",") }
            function layoutEdge(): string { return settingsPages.layoutEdge }
            function present(name: string): string { return settingsPages.present(name) ? "yes" : "no" }
        }

        // The material (K63; K59, K61): the shell's own Relief (linked from frontend/), under each opaque surface's content —
        // the ground first, then the header, the output strip, the sidebar and the section cards (SectionCard) each on
        // their fill — or, when the material runs through text and icons (`texture.text`), one layer over all of it
        // (`textRelief` below). The sheet's corners are the content's own (`root.cornerR`): the host does not clip it, since
        // an offscreen clip would move the relief off the shell's sheet.
        Loader {
            anchors.fill: parent
            active: Theme.surfaceRelief
            sourceComponent: Relief { radius: root.cornerR }
        }

        Column {
            id: keys
            anchors.fill: parent
            opacity: Store.live ? 1 : Theme.staleOpacity
            // Typing on the list starts a search (Ctrl+F does the same from anywhere).
            focus: true
            Keys.onPressed: event => {
                const printable = event.text.length === 1 && event.text >= " " && event.text !== "\x7f"
                if (printable && (event.modifiers & ~Qt.ShiftModifier) === 0) {
                    win.query += event.text
                    search.focusInput()
                    event.accepted = true
                }
            }

            // --- header ------------------------------------------------------------------------
            Rectangle {
                id: header
                width: parent.width
                height: 52
                color: Theme.container
                topLeftRadius: root.cornerR
                topRightRadius: root.cornerR
                Loader {
                    anchors.fill: parent
                    active: Theme.surfaceRelief
                    sourceComponent: Relief { topLeftRadius: root.cornerR; topRightRadius: root.cornerR }
                }
                // The sheet has no title bar: its own close button sits at the header's end (UX brief: Esc, the backdrop
                // or this button).
                Button {
                    id: closeButton
                    objectName: "sheet-close"
                    visible: win.sheet
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.pad
                    anchors.verticalCenter: parent.verticalCenter
                    width: height
                    label: Theme.iconFamily !== "" ? "" : "✕"
                    accessibleName: I18n.tr("settings.sheet.close")
                    onClicked: win.dismiss()
                    Text {
                        visible: Theme.iconFamily !== ""
                        anchors.centerIn: parent
                        font.family: Theme.iconFamily
                        font.pixelSize: Theme.fs + 6
                        color: Theme.fg
                        text: "close"
                    }
                }
                Row {
                    anchors.fill: parent
                    anchors.margins: Theme.pad
                    anchors.rightMargin: win.sheet ? closeButton.width + 2 * Theme.pad : Theme.pad
                    spacing: Theme.gap
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.fg
                        font.pixelSize: Theme.fsTitle
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("settings.ui.title")
                    }
                    TextField {
                        id: search
                        anchors.verticalCenter: parent.verticalCenter
                        width: 260
                        label: I18n.tr("settings.ui.search")
                        value: win.query
                        placeholder: I18n.tr("settings.ui.search")
                        onTyping: t => win.query = t
                        onSubmitted: win.jumpFirst()
                        escapeTaken: win.query !== ""
                        onEscaped: { win.query = ""; keys.forceActiveFocus() }
                    }
                    // Undo and redo are on while the daemon's config.history says there is something to take back. Redo
                    // stays off after a preview was put back: its step is the cancelled preview (Changes).
                    Button {
                        anchors.verticalCenter: parent.verticalCenter
                        label: I18n.tr("settings.ui.undo")
                        enabled: Store.live && Store.canUndo
                        onClicked: Store.undo()
                    }
                    Button {
                        anchors.verticalCenter: parent.verticalCenter
                        label: I18n.tr("settings.ui.redo")
                        enabled: Store.live && Store.redoShown
                        onClicked: Store.redo()
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.gap
                        Text {
                            height: Theme.controlH
                            verticalAlignment: Text.AlignVCenter
                            color: Theme.fg
                            font.pixelSize: Theme.fs
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.tr("settings.ui.advanced")
                        }
                        Item {
                            width: 40
                            height: Theme.controlH
                            Toggle {
                                anchors.verticalCenter: parent.verticalCenter
                                label: I18n.tr("settings.ui.advanced")
                                checked: win.advanced
                                onToggled: v => win.advanced = v
                            }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, parent.width - x - Theme.pad)
                        elide: Text.ElideRight
                        color: Store.notice !== "" || !Store.live ? Theme.error : Theme.dim
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: !Store.live ? I18n.tr("settings.ui.disconnected") : Store.notice
                    }
                }
            }

            // --- output picker (per_output rows) -------------------------------------------
            Rectangle {
                visible: Store.outputNames().length > 0
                width: parent.width
                height: visible ? 40 : 0
                // On the ground (its colour, its relief).
                color: "transparent"
                Row {
                    anchors.fill: parent
                    anchors.margins: Theme.gap
                    spacing: Theme.gap
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.dim
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("settings.ui.output")
                    }
                    Segmented {
                        anchors.verticalCenter: parent.verticalCenter
                        choices: [{ value: "", label: "settings.ui.all_outputs" }].concat(
                            Store.outputNames().map(function (n) { return { value: n, label: n } }))
                        current: win.output
                        onPicked: v => win.output = v
                        onPreviewed: v => win.output = v
                        cancellable: false
                    }
                }
            }

            Row {
                width: parent.width
                height: parent.height - 52 - (Store.outputNames().length > 0 ? 40 : 0)

                // --- sidebar -----------------------------------------------------------------
                Rectangle {
                    width: 220
                    height: parent.height
                    color: Theme.container
                    bottomLeftRadius: root.cornerR
                    Loader {
                        anchors.fill: parent
                        active: Theme.surfaceRelief
                        sourceComponent: Relief { bottomLeftRadius: root.cornerR }
                    }
                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.gap
                        spacing: 2
                        Repeater {
                            model: win.navItems
                            delegate: Column {
                                id: navEntry
                                required property var modelData
                                required property int index
                                width: parent.width
                                spacing: 2
                                // A separator before the views that are not pages (Changed, Mods, Profiles).
                                Item {
                                    visible: navEntry.modelData.id === "@changed"
                                    width: parent.width
                                    height: visible ? Theme.gap + 1 : 0
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: 1
                                        color: Theme.containerHigh
                                    }
                                }
                                Rectangle {
                                    id: entry
                                    readonly property bool on: !win.searching && navEntry.modelData.id === win.current
                                    // A mod's page (K25) shows its state: a filled dot = on, a hollow ring = loaded, off.
                                    // The shape carries it; the colour (color.status.*) only repeats it.
                                    readonly property bool isMod: navEntry.modelData.mod !== ""
                                    readonly property bool modOn: isMod && Store.modOn(navEntry.modelData.mod)
                                    readonly property string shownName: isMod ? I18n.tr(navEntry.modelData.label)
                                        : navEntry.modelData.id === "@changed" ? I18n.fmt("settings.ui.changed_count", { n: win.changedCount })
                                        : I18n.pageTitle(navEntry.modelData.id, navEntry.modelData.label)
                                    function open(): void { win.page = navEntry.modelData.id; win.query = "" }
                                    width: parent.width
                                    height: Theme.controlH + 4
                                    radius: height / 2
                                    // Tonal pill for the open page (I51); keycap chrome outlines it.
                                    color: on ? Theme.selected : (navHover.hovered ? Theme.containerHigh : "transparent")
                                    border.width: on && Theme.outlineW > 0 ? Theme.outlineW : 0
                                    border.color: Theme.line
                                    HoverHandler { id: navHover }
                                    // A Material Symbols icon per core page (none for mods and the views without one).
                                    readonly property string icon: ({
                                        layout: "toolbar", appearance: "palette", accessibility: "accessibility_new",
                                        island: "toggle_on", notifications: "notifications", launcher: "apps",
                                        clock: "schedule", desktop: "desktop_windows", power: "power_settings_new", dock: "dock_to_bottom", sidebar: "side_navigation", keys: "keyboard", "@changed": "history",
                                        "@mods": "extension", "@profiles": "person"
                                    })[navEntry.modelData.id] || ""
                                    activeFocusOnTab: true
                                    Keys.onReturnPressed: event => { entry.open(); event.accepted = true }
                                    Keys.onEnterPressed: event => { entry.open(); event.accepted = true }
                                    Keys.onSpacePressed: event => { entry.open(); event.accepted = true }
                                    Accessible.role: Accessible.PageTab
                                    Accessible.name: isMod
                                        ? I18n.fmt("settings.ui.mod_nav", { name: shownName, state: I18n.tr(modOn ? "settings.ui.on" : "settings.ui.off") })
                                        : shownName
                                    // The selected page is a tonal pill with a bold label, so the choice is not colour alone.
                                    Text {
                                        id: navIcon
                                        visible: Theme.iconFamily !== "" && entry.icon !== "" && !entry.isMod
                                        x: Theme.pad
                                        anchors.verticalCenter: parent.verticalCenter
                                        font.family: Theme.iconFamily
                                        font.pixelSize: Theme.fs + 6
                                        font.variableAxes: ({ "FILL": entry.on ? 1 : 0 })
                                        color: entry.on ? Theme.fgOnSelected : Theme.dim
                                        text: entry.icon
                                    }
                                    Rectangle {
                                        visible: entry.isMod
                                        x: Theme.pad
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 10
                                        height: 10
                                        radius: 5
                                        color: entry.modOn ? Theme.statusOn : "transparent"
                                        border.width: 2
                                        border.color: entry.modOn ? Theme.statusOn : Theme.statusOff
                                    }
                                    Text {
                                        x: entry.isMod ? Theme.pad + 18 : (navIcon.visible ? Theme.pad + 28 : Theme.pad)
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - x - Theme.pad
                                        elide: Text.ElideRight
                                        color: entry.on ? Theme.fgOnSelected : Theme.dim
                                        font.weight: entry.on ? Theme.wBold : Theme.wMedium
                                        font.pixelSize: Theme.fs
                                        font.family: Theme.fam(text, Theme.families)
                                        text: entry.shownName
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: entry.open()
                                    }
                                    FocusRing {
                                        anchors.fill: parent
                                        shown: entry.activeFocus
                                        corner: entry.radius
                                    }
                                }
                            }
                        }
                    }
                }

                // --- content -----------------------------------------------------------------
                Item {
                    width: parent.width - 220
                    height: parent.height
                    SettingsPages {
                        id: settingsPages
                        anchors.fill: parent
                        visible: win.searching || !win.special
                        pageId: win.current
                        query: win.query
                        showAdvanced: win.advanced
                        output: win.output
                        onJumpRequested: (targetPage, row, byKeyboard) => win.jump(targetPage, row, byKeyboard)
                        onPageRequested: id => win.page = id
                    }
                    ChangedPage {
                        anchors.fill: parent
                        visible: !win.searching && win.current === "@changed"
                        onJumpRequested: (targetPage, row) => win.jump(targetPage, row, false)
                    }
                    ModsPage {
                        id: modsPage
                        anchors.fill: parent
                        visible: !win.searching && win.current === "@mods"
                    }
                    ProfilesPage {
                        id: profiles
                        anchors.fill: parent
                        visible: !win.searching && win.current === "@profiles"
                    }
                }
            }
        }
        // `texture.text`: the relief lies over everything Settings draws, text and icons included, as the shell's blocks
        // do in that mode (the surfaces' own reliefs are off then).
        Loader {
            anchors.fill: parent
            active: Theme.textRelief
            sourceComponent: Relief { radius: root.cornerR }
        }
    }
}
