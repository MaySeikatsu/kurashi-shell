import QtQuick
import qs.core
import qs.components

// What a place's well says while the terminal's text is not there (docs/ux/terminal.md "States"), as the shell's cards
// say an empty or a stopped state: a symbol on a tonal disc, one line, a detail where there is one, and the one action
// that helps — the host missing (its settings), starting (the look's loading line), stopped (start again; its sessions
// ended, said), the last shell exited (a new one; Enter does it too), or another place shows the terminal (show it here).
// Nothing is drawn while the terminal shows here: the host's text lies over the well then. A refused folder is not said
// here but in the place's notice strip (NoticeStrip), over the tab row, so it never stands under the terminal's text.
Item {
    id: n
    property var doc: ({})
    property string place: "dropdown"
    readonly property var host: doc.host || ({})
    readonly property string state: String(host.state || "off")
    readonly property bool crashed: host.crashed === true || state === "failed"
    readonly property bool hasTabs: (doc.tabs || []).length > 0
    readonly property string shownIn: doc.shown_in || ""
    readonly property bool elsewhere: shownIn !== "" && shownIn !== place && (doc.open || []).indexOf(place) >= 0
    // The state that holds, most pressing first.
    readonly property string what: state === "missing" ? "missing"
        : crashed ? "crashed"
        : elsewhere ? "elsewhere"
        : !hasTabs ? "exited"
        : state !== "ready" ? "starting"
        : ""
    readonly property bool alarm: what === "crashed" || what === "missing"
    function act() {
        if (what === "crashed") Store.act("terminal.restart", {})
        else if (what === "elsewhere") Store.act("terminal.bring", { where: place })
        else if (what === "exited") Store.act("terminal.new_tab", {})
        else if (what === "missing") Store.act("settings.open", { page: "mod:terminal" })
    }
    // The detail under the line: why the host stopped, or what Enter does.
    readonly property string detail: what === "crashed" ? String(host.detail || "")
        : what === "missing" ? I18n.tr("terminal.state.missing.detail")
        : what === "exited" ? I18n.tr("terminal.state.exited.detail") : ""

    // Enter does what the button says (the well holds no terminal now, so the keys are not a shell's).
    Keys.onReturnPressed: act()
    Keys.onEnterPressed: act()
    Accessible.role: Accessible.StaticText
    Accessible.name: line.text

    Column {
        visible: n.what !== ""
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.pad, 440)
        spacing: Theme.gap
        // The symbol on a tonal disc (an alarm in the error's tone).
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Theme.fs * 3
            height: width
            radius: width / 2
            color: n.alarm ? Qt.tint(Theme.containerHigh, Qt.alpha(Theme.error, 0.18)) : Theme.containerHigh
            border.width: Theme.surfaceLineW > 0 ? 1 : 0
            border.color: Theme.outline
            Icon {
                anchors.centerIn: parent
                name: n.what === "crashed" ? "restart_alt" : n.what === "missing" ? "extension_off"
                    : n.what === "elsewhere" ? "open_in_new" : "terminal"
                glyph: n.what === "crashed" ? "↻" : "›_"
                size: Theme.fs + 8
                color: n.alarm ? Theme.error : Theme.dim
            }
        }
        LoadingText {
            id: line
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            loading: n.what === "starting"
            words: n.what === "" ? "" : I18n.tr("terminal.state." + n.what)
                .replace("{place}", I18n.tr("terminal.place." + n.shownIn))
            color: Theme.fg
            font.pixelSize: Theme.fs + 1
            font.weight: Theme.wMedium
        }
        Text {
            visible: n.detail !== ""
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            text: n.detail
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }
        Item {
            visible: n.what !== "starting"
            width: parent.width
            height: visible ? press.height + Theme.xs : 0
            Button {
                id: press
                objectName: "terminal-notice-action"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                label: n.what === "" || n.what === "starting" ? "" : I18n.tr("terminal.press." + n.what)
                primary: n.what !== "missing"
                onClicked: n.act()
            }
        }
    }
}
