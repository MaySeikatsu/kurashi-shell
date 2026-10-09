import QtQuick
import Quickshell
import Quickshell.Io
import "core"
import "components"
import "pages"

// Settings app (K2): a separate, on-demand process; `qs -p settings`. A normal xdg toplevel, not a
// layer surface. Pages are generated from the daemon's `schema.settings` document (rule 3); this
// file only lays out chrome. The process ends when the window closes.
ShellRoot {
    FloatingWindow {
        id: win
        title: I18n.tr("settings.ui.title")
        implicitWidth: 1000
        implicitHeight: 720
        minimumSize: Qt.size(640, 420)
        color: Theme.surface
        onVisibleChanged: if (!visible) Qt.quit()

        Shortcut {
            sequence: "Ctrl+F"
            onActivated: search.focusInput()
        }

        // "" = first schema page; "@mods" and "@profiles" = the Mods and profiles pages.
        property string page: ""
        property string query: ""
        property bool advanced: false
        property string output: ""
        readonly property var pages: Store.schema.pages || []
        readonly property string current: page !== "" ? page : (pages.length ? pages[0].id : "")
        readonly property bool searching: query.trim() !== ""

        // A search hit was chosen (Enter, or a click on its breadcrumb): leave the search, open the
        // row's page (an advanced row needs the advanced view) and bring the row into view.
        function jump(pageId: string, row: var): void {
            if (row.advanced) win.advanced = true
            win.query = ""
            win.page = pageId
            settingsPages.reveal(row.key)
        }
        function jumpFirst(): void {
            if (!win.searching) return
            const h = settingsPages.firstHit()
            if (h) win.jump(h.pageId, h.row)
        }

        // Test/automation hook: `qs -p settings ipc call settings <fn> ...`. Goes through the same
        // paths as the controls (Store.setValue, page selection), so it exercises the real UI.
        IpcHandler {
            target: "settings"
            function goto(id: string): void { win.page = id; win.query = "" }
            function find(q: string): void { win.query = q }
            function set(key: string, json: string): void {
                Store.setValue(key, JSON.parse(json), win.output)
            }
            function output(name: string): void { win.output = name }
            function advanced(on: bool): void { win.advanced = on }
            function preview(name: string): void { win.page = "@profiles"; profiles.select(name) }
            function jump(key: string): void {
                const h = Store.rowOf(key)
                if (h) win.jump(h.pageId, h.row)
            }
            function mod(id: string, on: bool): void { modsPage.setEnabled(id, on) }
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
                return "undo=" + (Store.canUndo ? "on" : "off") + ",redo=" + (Store.canRedo ? "on" : "off")
            }
            function undo(): void { Store.undo() }
            // Profiles test: the names the Profiles page lists now.
            function profileNames(): string { return profiles.profiles.map(function (x) { return x.name }).join(",") }
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

            // --- header --------------------------------------------------------------------
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
                    // Undo and redo are on while the daemon's config.history says there is something to take back.
                    Button {
                        anchors.verticalCenter: parent.verticalCenter
                        label: I18n.tr("settings.ui.undo")
                        enabled: Store.live && Store.canUndo
                        onClicked: Store.undo()
                    }
                    Button {
                        anchors.verticalCenter: parent.verticalCenter
                        label: I18n.tr("settings.ui.redo")
                        enabled: Store.live && Store.canRedo
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
                        color: Theme.error
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
                            model: win.pages.map(function (p) { return { id: p.id, label: p.label } })
                                .concat([{ id: "@mods", label: "settings.ui.mods" },
                                         { id: "@profiles", label: "settings.ui.profiles" }])
                            delegate: Rectangle {
                                id: entry
                                required property var modelData
                                readonly property bool on: !win.searching && modelData.id === win.current
                                function open(): void { win.page = modelData.id; win.query = "" }
                                width: parent.width
                                height: Theme.controlH
                                radius: Theme.rSm
                                color: on ? Theme.containerHigh : "transparent"
                                activeFocusOnTab: true
                                Keys.onReturnPressed: event => { entry.open(); event.accepted = true }
                                Keys.onEnterPressed: event => { entry.open(); event.accepted = true }
                                Keys.onSpacePressed: event => { entry.open(); event.accepted = true }
                                Accessible.role: Accessible.PageTab
                                Accessible.name: I18n.pageTitle(modelData.id, modelData.label)
                                Text {
                                    x: Theme.pad
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: entry.on ? Theme.fg : Theme.dim
                                    font.pixelSize: Theme.fs
                                    font.family: Theme.fam(text, Theme.families)
                                    text: I18n.pageTitle(modelData.id, modelData.label)
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

                // --- content -----------------------------------------------------------------
                Item {
                    width: parent.width - 220
                    height: parent.height
                    SettingsPages {
                        id: settingsPages
                        anchors.fill: parent
                        visible: win.searching || (win.current !== "@profiles" && win.current !== "@mods")
                        pageId: win.current
                        query: win.query
                        showAdvanced: win.advanced
                        output: win.output
                        onJumpRequested: (targetPage, row) => win.jump(targetPage, row)
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
