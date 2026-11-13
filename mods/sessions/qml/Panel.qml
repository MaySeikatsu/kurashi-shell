import QtQuick
import Quickshell
import qs.core
import qs.components

// The sessions as a panel (`panel:sessions` → `mod:sessions:sessions`; docs/ux/sessions.md "Glances"): the bar module's
// card, a sidebar section, the desktop menu's "Open project…". noren's sessions and folders with their state; a row opens
// (the "Open in…" step), its keys pin, snapshot and kill (kill asks once more); the header saves and restores the current
// project's desk. Opening the panel reads the list again (never a timer: Ma). Without noren: the reason and the option.
Item {
    id: panel
    required property var store
    required property var theme
    required property var i18n
    property real fillHeight: 0
    property var placement: null
    property var cardPlacement: null

    width: parent ? parent.width : 420
    implicitWidth: 420
    implicitHeight: fillHeight > 0 ? fillHeight : Math.min(520, col.implicitHeight + 2 * Theme.pad)

    Watch { doc: "mod.sessions" }
    readonly property var d: Store.docs["mod.sessions"] || ({})
    readonly property var noren: d.noren || ({})
    readonly property bool missing: noren.state === "missing"
    readonly property var entries: d.entries || []
    readonly property var cur: d.current || null
    readonly property bool curDesk: !!(cur && d.desks && d.desks[cur.project])
    readonly property bool deskOn: !!(d.desk && d.desk.available)
    readonly property string output: cardPlacement ? String(cardPlacement.output || "") : (placement ? String(placement.output || "") : "")
    Component.onCompleted: if (!missing) Store.act("sessions.refresh")

    function stateWord(e) {
        var k = e.state === "idle" ? (e.kind === "config" ? "config" : "folder") : e.state
        return I18n.tr("sessions.state." + k)
    }
    function stateIcon(e) {
        if (e.pinned) return "push_pin"
        if (e.state === "attached") return "terminal"
        if (e.state === "running") return "play_arrow"
        if (e.state === "exited") return "history"
        return e.kind === "config" ? "settings" : "folder"
    }
    function noticeText() {
        var n = d.notice
        if (!n) return ""
        return I18n.tr(n.key).replace("{detail}", n.detail || "")
    }
    function open(e) {
        var a = { key: e.key }
        if (output !== "") a.output = output
        Store.act("sessions.open", a)
    }
    property string killArmed: ""
    Timer { id: unarm; interval: 3000; onTriggered: panel.killArmed = "" }

    Column {
        id: col
        x: Theme.pad
        y: Theme.pad
        width: parent.width - 2 * Theme.pad
        spacing: Theme.gap

        // The header: the title, the current project and its desk.
        Item {
            width: parent.width
            height: 32
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("sessions.panel.title")
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.xs
                IconButton {
                    visible: !panel.missing
                    icon: "save"
                    a11y: panel.cur ? I18n.tr("sessions.panel.save.a11y").replace("{name}", panel.cur.name) : I18n.tr("sessions.panel.no_current")
                    enabled: !!panel.cur && panel.deskOn
                    onClicked: Store.act("sessions.desk.save", { project: panel.cur.project })
                }
                IconButton {
                    visible: !panel.missing && panel.curDesk
                    icon: "restore"
                    a11y: I18n.tr("sessions.panel.restore")
                    enabled: panel.deskOn && !panel.d.restoring
                    onClicked: Store.act("sessions.desk.restore", { project: panel.cur.project })
                }
                IconButton {
                    visible: !panel.missing
                    icon: "refresh"
                    a11y: I18n.tr("sessions.panel.refresh")
                    onClicked: Store.act("sessions.refresh")
                }
            }
        }
        // What is current, what the desk can do, what went wrong.
        Text {
            width: parent.width
            visible: text !== ""
            wrapMode: Text.WordWrap
            text: panel.missing ? I18n.tr(panel.noren.reason || "sessions.state.missing")
                : (panel.d.restoring ? I18n.tr("sessions.panel.restoring")
                : (panel.noticeText() !== "" ? panel.noticeText()
                : (!panel.deskOn && panel.d.desk ? I18n.tr(panel.d.desk.reason || "")
                : (panel.cur ? I18n.tr("sessions.panel.current").replace("{name}", panel.cur.name)
                    + (panel.curDesk ? " · " + I18n.tr("sessions.panel.desk").replace("{n}", panel.d.desks[panel.cur.project].windows) : "")
                : I18n.tr("sessions.panel.no_current")))))
            color: panel.missing || (panel.d.notice && /failed|not_opened|spawn|noren/.test(panel.d.notice.key)) ? Theme.error : Theme.dim
            font.pixelSize: Theme.fsLabel
        }
        // Nothing to list yet.
        Column {
            width: parent.width
            visible: !panel.missing && panel.entries.length === 0 && panel.noren.state === "ready"
            spacing: 2
            Text { text: I18n.tr("sessions.panel.empty"); color: Theme.fg; font.pixelSize: Theme.fs }
            Text { width: parent.width; wrapMode: Text.WordWrap; text: I18n.tr("sessions.panel.empty.sub"); color: Theme.dim; font.pixelSize: Theme.fsLabel }
        }
        LoadingText {
            visible: panel.noren.state === "loading"
            loading: visible
            words: I18n.tr("sessions.state.loading")
        }

        ListView {
            id: list
            width: parent.width
            height: Math.min(contentHeight, (panel.fillHeight > 0 ? panel.fillHeight : 520) - y - 2 * Theme.pad)
            visible: !panel.missing && count > 0
            clip: true
            interactive: contentHeight > height
            model: panel.entries
            spacing: 2
            keyNavigationEnabled: true
            activeFocusOnTab: true
            Keys.onReturnPressed: if (currentIndex >= 0) panel.open(panel.entries[currentIndex])
            Keys.onEnterPressed: if (currentIndex >= 0) panel.open(panel.entries[currentIndex])
            highlight: Block {
                width: list.width
                radius: Theme.rLg
                ringScale: 0
                softScale: 0
                fill: Theme.selected
                visible: list.activeFocus
                penSeed: 0x5E56
            }
            delegate: Item {
                id: r
                required property var modelData
                required property int index
                readonly property var e: modelData
                readonly property bool live: e.state === "attached" || e.state === "running"
                readonly property bool session: e.kind === "session"
                width: list.width
                height: 46
                opacity: e.missing ? 0.55 : 1
                Accessible.role: Accessible.ListItem
                Accessible.name: I18n.tr("sessions.panel.row.a11y").replace("{name}", e.name).replace("{state}", e.missing ? I18n.tr("sessions.launcher.missing_dir") : panel.stateWord(e)).replace("{dir}", e.dir || "")
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.rSm
                    color: hover.containsMouse ? Qt.alpha(Theme.fg, 0.06) : "transparent"
                }
                Icon {
                    id: ic
                    x: Theme.gap
                    anchors.verticalCenter: parent.verticalCenter
                    name: panel.stateIcon(r.e)
                    filled: r.e.state === "attached"
                    color: r.live ? Theme.accent : Theme.dim
                }
                Column {
                    x: ic.x + 32
                    width: keys.x - x - Theme.gap
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: r.e.name
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideMiddle
                        text: (r.e.missing ? I18n.tr("sessions.launcher.missing_dir") : panel.stateWord(r.e)) + (r.e.dir ? " · " + r.e.dir : "")
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                    }
                }
                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !r.e.missing
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { list.currentIndex = r.index; panel.open(r.e) }
                }
                Row {
                    id: keys
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.xs
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    visible: hover.containsMouse || list.currentIndex === r.index || panel.killArmed === r.e.key
                    IconButton {
                        visible: r.e.desk === true
                        icon: "restore"
                        a11y: I18n.tr("sessions.panel.restore")
                        enabled: panel.deskOn
                        onClicked: Store.act("sessions.desk.restore", { project: r.e.path || ("session:" + r.e.name) })
                    }
                    IconButton {
                        icon: "push_pin"
                        lit: r.e.pinned === true
                        a11y: I18n.tr(r.e.pinned ? "sessions.panel.unpin" : "sessions.panel.pin")
                        onClicked: Store.act("sessions.pin", { key: r.e.key })
                    }
                    IconButton {
                        visible: r.session && r.e.state !== "idle"
                        icon: "backup"
                        a11y: I18n.tr("sessions.panel.snapshot")
                        onClicked: Store.act("sessions.snapshot", { key: r.e.key })
                    }
                    IconButton {
                        visible: r.session && r.live
                        icon: "stop_circle"
                        lit: panel.killArmed === r.e.key
                        a11y: I18n.tr(panel.killArmed === r.e.key ? "sessions.panel.kill.confirm" : "sessions.panel.kill")
                        onClicked: {
                            if (panel.killArmed !== r.e.key) { panel.killArmed = r.e.key; unarm.restart(); return }
                            panel.killArmed = ""
                            Store.act("sessions.kill", { key: r.e.key })
                        }
                    }
                    IconButton {
                        visible: r.e.open_in !== undefined
                        icon: "history"
                        a11y: I18n.tr("sessions.panel.ask_again")
                        onClicked: Store.act("sessions.forget", { project: r.e.path || ("session:" + r.e.name) })
                    }
                }
            }
        }
    }
}
