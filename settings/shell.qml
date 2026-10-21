import QtQuick
import Quickshell
import Quickshell.Io
import "core"
import "components"
import "pages"

// Settings app (K2): a separate, on-demand process; `qs -p settings`. A normal xdg toplevel, not a layer surface. Pages are
// generated from the daemon's `schema.settings` document (rule 3); this file lays out the chrome. The process ends when the
// window closes. `KURASHI_SETTINGS_KEY=<key> qs -p settings` opens that setting's row at start; a running window takes the
// same link through `qs -p settings ipc call settings jump <key>`; `kurashi settings <key>` and the daemon action
// `settings.open {key}` do either for you (K32).
ShellRoot {
    FloatingWindow {
        id: win
        title: I18n.tr("settings.ui.title")
        implicitWidth: 1040
        implicitHeight: 740
        minimumSize: Qt.size(640, 420)
        color: Theme.surface
        // Closing the window ends an open preview: the value it started from comes back, as Esc would do.
        onVisibleChanged: if (!visible) { Changes.putBack(); Qt.quit() }

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
        // Leaving a page, searching or closing ends a preview (Changes): it is put back. A query the app cleared (a jump, a
        // page change) clears the field too, even while the field has the focus (its text follows the query only then).
        onPageChanged: Changes.putBack()
        onQueryChanged: {
            if (query !== "") Changes.putBack()
            else search.clear()
        }

        // A deep link given at start is opened once the schema has arrived.
        property bool startKeyDone: false
        readonly property string startKey: Quickshell.env("KURASHI_SETTINGS_KEY") || ""
        Connections {
            target: Store
            function onSchemaChanged() {
                if (!win.startKeyDone && win.startKey !== "" && Store.rowOf(win.startKey)) {
                    win.startKeyDone = true
                    win.openKey(win.startKey)
                }
            }
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
            // Start-up state for the deep link test: the key the environment named, and whether it was opened.
            function dbg(): string {
                return "startKey=" + win.startKey + ",done=" + win.startKeyDone + ",schemaPages=" + win.pages.length
                    + ",rowOf=" + (Store.rowOf(win.startKey) ? "yes" : "no")
            }
            function advanced(on: bool): void { win.advanced = on }
            function preview(name: string): void { win.page = "@profiles"; profiles.select(name) }
            function jump(key: string): void { win.openKey(key) }
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
                width: parent.width
                height: 52
                color: Theme.container
                Row {
                    anchors.fill: parent
                    anchors.margins: Theme.pad
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
                color: Theme.surface
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
                                        bar: "toolbar", appearance: "palette", accessibility: "accessibility_new",
                                        island: "toggle_on", notifications: "notifications", launcher: "apps",
                                        clock: "schedule", desktop: "desktop_windows", power: "power_settings_new", dock: "dock_to_bottom", "@changed": "history",
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
    }
}
