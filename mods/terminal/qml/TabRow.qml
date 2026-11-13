import QtQuick
import qs.core
import qs.components

// The terminal's tab row (docs/ux/terminal.md "Tabs"): a key per tab (the shell's title, else its directory's last part;
// a rename sticks), "+" (a new tab; its menu lists the favourite directories), and the pin. A click selects, a middle
// click closes, a double click renames in place; × closes the hovered or focused one. Every key is a tab stop with a name.
Item {
    id: tr
    property var doc: ({})
    property string output: ""
    readonly property var tabs: doc.tabs || []
    readonly property string active: doc.active || ""
    readonly property var s: doc.settings || ({})
    readonly property bool pinned: s.pinned === true
    readonly property bool pinForced: !!(doc.forced && doc.forced.pinned)
    implicitHeight: Theme.barH - 6
    height: implicitHeight

    function nameOf(t) {
        if (t.title) return String(t.title)
        var p = String(t.cwd || t.dir || "")
        var parts = p.split("/").filter(function (x) { return x !== "" })
        return parts.length ? parts[parts.length - 1] : "/"
    }

    Flickable {
        id: strip
        anchors.left: parent.left
        anchors.right: tools.left
        anchors.rightMargin: Theme.gap
        height: parent.height
        contentWidth: keys.width
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Row {
            id: keys
            spacing: Theme.xs
            height: parent.height
            Repeater {
                model: tr.tabs
                delegate: Item {
                    id: key
                    required property var modelData
                    required property int index
                    readonly property bool on: modelData.id === tr.active
                    property bool editing: false
                    width: Math.min(220, Math.max(96, label.implicitWidth + 2 * Theme.pad + close.width))
                    height: keys.height
                    activeFocusOnTab: true
                    Accessible.role: Accessible.PageTab
                    Accessible.name: I18n.tr("terminal.tab.a11y").replace("{n}", String(index + 1))
                        .replace("{of}", String(tr.tabs.length)).replace("{title}", tr.nameOf(modelData))
                    Accessible.selected: on
                    Keys.onReturnPressed: Store.act("terminal.select", { tab: modelData.id })
                    Keys.onSpacePressed: Store.act("terminal.select", { tab: modelData.id })
                    Keys.onDeletePressed: Store.act("terminal.close_tab", { tab: modelData.id })
                    Keys.onPressed: e => { if (e.key === Qt.Key_F2) { key.editing = true; e.accepted = true } }
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.rSm
                        color: key.on ? Qt.alpha(Theme.accent, 0.22) : (hov.hovered ? Qt.alpha(Theme.fg, 0.08) : "transparent")
                        border.width: key.on ? 1 : 0
                        border.color: Qt.alpha(Theme.accent, 0.6)
                    }
                    Text {
                        id: label
                        visible: !key.editing
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.pad
                        width: parent.width - 2 * Theme.pad - close.width
                        elide: Text.ElideRight
                        text: tr.nameOf(key.modelData)
                        color: key.on ? Theme.fg : Theme.dim
                        font.pixelSize: Theme.fsLabel
                        font.family: Theme.fam(text, Theme.families)
                    }
                    TextInput {
                        id: edit
                        visible: key.editing
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.pad
                        width: parent.width - 2 * Theme.pad
                        color: Theme.fg
                        font.pixelSize: Theme.fsLabel
                        font.family: Theme.fam(text, Theme.families)
                        selectByMouse: true
                        onVisibleChanged: if (visible) { text = tr.nameOf(key.modelData); selectAll(); forceActiveFocus() }
                        Keys.onReturnPressed: { Store.act("terminal.rename", { tab: key.modelData.id, title: text }); key.editing = false }
                        Keys.onEscapePressed: key.editing = false
                        onActiveFocusChanged: if (!activeFocus) key.editing = false
                        Accessible.name: I18n.tr("terminal.tab.rename")
                    }
                    IconButton {
                        id: close
                        visible: hov.hovered || key.activeFocus || key.on
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 2
                        scale: 0.75
                        icon: "close"
                        glyph: "×"
                        a11y: I18n.tr("terminal.tab.close")
                        onClicked: Store.act("terminal.close_tab", { tab: key.modelData.id })
                    }
                    HoverHandler { id: hov }
                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onTapped: Store.act("terminal.select", { tab: key.modelData.id })
                        onDoubleTapped: key.editing = true
                    }
                    TapHandler {
                        acceptedButtons: Qt.MiddleButton
                        onTapped: Store.act("terminal.close_tab", { tab: key.modelData.id })
                    }
                    FocusRing { anchors.fill: parent; shown: key.activeFocus; corner: Theme.rSm }
                }
            }
        }
    }

    Row {
        id: tools
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.xs
        IconButton {
            id: plus
            icon: "add"
            glyph: "+"
            a11y: I18n.tr("terminal.tab.new")
            onClicked: Store.act("terminal.new_tab", {})
        }
        // The favourite directories, one key each (a new tab there, or `cd` here: `dir_opens`).
        Repeater {
            model: tr.s.favourites || []
            delegate: IconButton {
                required property var modelData
                icon: "folder"
                glyph: "▤"
                enabled: modelData.missing !== true
                a11y: modelData.missing === true
                    ? I18n.tr("terminal.dir.missing").replace("{path}", String(modelData.path))
                    : I18n.tr("terminal.dir.open").replace("{label}", String(modelData.label))
                onClicked: Store.act("terminal.open_dir", { path: modelData.path, output: tr.output })
            }
        }
        IconButton {
            icon: "push_pin"
            glyph: "⊙"
            lit: tr.pinned
            enabled: !tr.pinForced
            a11y: tr.pinForced ? I18n.tr("terminal.pin.forced").replace("{by}", String(tr.doc.forced.pinned))
                : (tr.pinned ? I18n.tr("terminal.pin.off") : I18n.tr("terminal.pin.on"))
            onClicked: Store.act("terminal.pin", {})
        }
    }
}
