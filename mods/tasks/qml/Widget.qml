import QtQuick
import qs.core
import qs.components

// Bar widget of the tasks mod (docs/ux/tasks.md, Design): a checklist icon, and the open count next to it (under it on a
// side bar) when `mods.tasks.bar_count` is on. A click (Return, Enter, Space) opens the panel. A file that cannot be read
// shows "!" in place of the count, and the accessible name says why. Visible = subscribed (Ma).
Item {
    // Handed in by ModLoader (K26 loader contract).
    required property var store
    required property var theme
    required property var i18n
    id: w
    property bool vertical: false

    property bool live: visible
    Watch { doc: "mod.tasks"; active: w.live }

    readonly property var d: Store.docs["mod.tasks"] || ({})
    readonly property bool loaded: Store.docs["mod.tasks"] !== undefined && d.state !== undefined
    readonly property bool failed: d.state === "error"
    readonly property var cfg: (Store.docs["config"] && Store.docs["config"].values) || ({})
    readonly property bool showCount: cfg["mods.tasks.bar_count"] !== undefined && cfg["mods.tasks.bar_count"].value === true
    readonly property int open: d.open || 0
    readonly property string countText: !loaded ? "" : failed ? "!" : String(open)

    function fill(s, vars) {
        return String(s).replace(/\{(\w+)\}/g, function (m, k) { return vars[k] !== undefined ? String(vars[k]) : m })
    }
    function openPanel() { Store.act("mod.panel.open", { id: "tasks", panel: "tasks" }) }

    implicitWidth: w.vertical ? Theme.barH : row.implicitWidth + Theme.gap * 2
    implicitHeight: w.vertical ? col.implicitHeight : Theme.controlH
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: !loaded ? I18n.tr("mod-tasks.loading")
        : failed ? I18n.tr(d.reason || "mod-tasks.error.read")
        : fill(I18n.tr("mod-tasks.a11y.widget"), { n: open })
    Keys.onReturnPressed: w.openPanel()
    Keys.onEnterPressed: w.openPanel()
    Keys.onSpacePressed: w.openPanel()

    Row {
        id: row
        visible: !w.vertical
        anchors.centerIn: parent
        spacing: Theme.xs
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "checklist"
            glyph: "☑"
            color: w.failed ? Theme.error : Theme.fg
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: w.showCount && w.countText !== ""
            color: w.failed ? Theme.error : Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            font.features: ({"tnum": 1})
            text: w.countText
        }
    }
    Column {
        id: col
        visible: w.vertical
        anchors.centerIn: parent
        Icon {
            width: Theme.barH
            name: "checklist"
            glyph: "☑"
            color: w.failed ? Theme.error : Theme.fg
        }
        Text {
            visible: w.showCount && w.countText !== ""
            width: Theme.barH
            horizontalAlignment: Text.AlignHCenter
            color: w.failed ? Theme.error : Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            font.features: ({"tnum": 1})
            text: w.countText
        }
    }

    FocusRing { anchors.fill: parent; shown: w.activeFocus; corner: Theme.rSm }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: w.openPanel()
    }
}
