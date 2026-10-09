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

        // "" = first schema page; "@profiles" = the profiles page.
        property string page: ""
        property string query: ""
        property bool advanced: false
        property string output: ""
        readonly property var pages: Store.schema.pages || []
        readonly property string current: page !== "" ? page : (pages.length ? pages[0].id : "")
        readonly property bool searching: query.trim() !== ""

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
        }

        Column {
            anchors.fill: parent
            opacity: Store.live ? 1 : Theme.staleOpacity

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
                        anchors.verticalCenter: parent.verticalCenter
                        width: 260
                        value: win.query
                        placeholder: I18n.tr("settings.ui.search")
                        onTyping: t => win.query = t
                    }
                    Button {
                        anchors.verticalCenter: parent.verticalCenter
                        label: I18n.tr("settings.ui.undo")
                        enabled: Store.live
                        onClicked: Store.undo()
                    }
                    Button {
                        anchors.verticalCenter: parent.verticalCenter
                        label: I18n.tr("settings.ui.redo")
                        enabled: Store.live
                        onClicked: Store.redo()
                    }
                    Button {
                        anchors.verticalCenter: parent.verticalCenter
                        label: (win.advanced ? "✓ " : "") + I18n.tr("settings.ui.advanced")
                        onClicked: win.advanced = !win.advanced
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
                                .concat([{ id: "@profiles", label: "settings.ui.profiles" }])
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool on: !win.searching && modelData.id === win.current
                                width: parent.width
                                height: 32
                                radius: Theme.rSm
                                color: on ? Theme.containerHigh : "transparent"
                                Text {
                                    x: Theme.pad
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: parent.on ? Theme.fg : Theme.dim
                                    font.pixelSize: Theme.fs
                                    font.family: Theme.fam(text, Theme.families)
                                    text: I18n.tr(modelData.label)
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: { win.page = modelData.id; win.query = "" }
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
                        anchors.fill: parent
                        visible: win.searching || win.current !== "@profiles"
                        pageId: win.current
                        query: win.query
                        showAdvanced: win.advanced
                        output: win.output
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
