import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.components.island

// The terminal's tab row (docs/ux/terminal.md "Tabs"), in the shell's own tab style — the sidebar's tab row (I500): one
// row of keys, the current one tonal (`Theme.selected`), the others the look's keys; tabs that do not fit scroll sideways
// (wheel or drag), their cut end blending out as any scroll edge does, the current one always brought into view. At its
// end "+" (a new tab) and its menu (⌄, or a right click on "+": a new tab, a new tab in a favourite folder, the folders'
// settings), then the pin while the drop-down carries it. A tab: a click selects it, a middle click closes it, a double
// click (or F2) renames it in place; its × shows on the current one, on hover and on focus. Every key is a tab stop with
// a name; Ctrl+PageUp/PageDown step through the tabs from any of them.
Item {
    id: tr
    property var doc: ({})
    property string output: ""
    // The pin is the drop-down's (it keeps it out through a click elsewhere); the card has the Stage's own pin.
    property bool showPin: false
    readonly property var tabs: doc.tabs || []
    readonly property string active: doc.active || ""
    readonly property var s: doc.settings || ({})
    readonly property bool pinned: s.pinned === true
    readonly property bool pinForced: !!(doc.forced && doc.forced.pinned)
    readonly property int activeIndex: {
        for (var i = 0; i < tabs.length; i++) if (tabs[i].id === active) return i
        return -1
    }
    // A tab's name is being edited: the place hands this row the keyboard meanwhile.
    property bool editing: false
    // The "+" menu is open (a place keeps its card while its menu is out).
    readonly property bool menuOpen: plusMenu.open
    readonly property real keyH: 30
    implicitHeight: keyH + Theme.shadowDy
    height: implicitHeight

    function nameOf(t) {
        if (t.title) return String(t.title)
        var p = String(t.cwd || t.dir || "")
        var parts = p.split("/").filter(function (x) { return x !== "" })
        return parts.length ? parts[parts.length - 1] : "/"
    }
    function tail(p) {
        var parts = String(p || "").split("/").filter(function (x) { return x !== "" })
        return parts.length ? parts[parts.length - 1] : "/"
    }
    function step(by) { Store.act("terminal.select", { step: by }) }
    Keys.onPressed: event => {
        if (!(event.modifiers & Qt.ControlModifier)) return
        if (event.key === Qt.Key_PageDown) { step(1); event.accepted = true }
        else if (event.key === Qt.Key_PageUp) { step(-1); event.accepted = true }
    }

    // ---- the "+" menu: a new tab, the favourite folders (a missing one grey, said why), their settings ----
    readonly property var favourites: s.favourites || []
    function menuTree() {
        var kids = [{ id: 1, label: I18n.tr("terminal.tab.new") }]
        if (favourites.length > 0) {
            kids.push({ id: 2, separator: true })
            for (var i = 0; i < favourites.length; i++) {
                var f = favourites[i], name = String(f.label || "") !== "" ? String(f.label) : tail(f.path)
                kids.push({ id: 100 + i, enabled: f.missing !== true,
                            label: f.missing === true ? I18n.tr("terminal.menu.dir_missing").replace("{label}", name)
                                                      : I18n.tr("terminal.dir.open").replace("{label}", name) })
            }
        }
        kids.push({ id: 3, separator: true })
        kids.push({ id: 4, label: I18n.tr(favourites.length > 0 ? "terminal.menu.edit_favourites" : "terminal.menu.add_favourites") })
        return { children: kids }
    }
    function openMenu() {
        if (plusMenu.open) { plusMenu.close(); return }
        var w = tr.QsWindow.window
        if (!w) return
        var o = Light.originOf(w)
        var p = tools.mapToItem(null, 0, 0)
        plusMenu.show(w.screen, { x: o.x + p.x, y: o.y + p.y, width: tools.width, height: tr.keyH }, menuTree(),
                      "", I18n.tr("terminal.menu.title"))
    }
    TermMenu {
        id: plusMenu
        onChosen: id => {
            if (id === 1) Store.act("terminal.new_tab", {})
            else if (id === 4) Store.act("settings.open", { page: "mod:terminal" })
            else if (id >= 100 && id - 100 < tr.favourites.length)
                Store.act("terminal.open_dir", { path: tr.favourites[id - 100].path, output: tr.output })
        }
    }

    ScrollEdge { view: strip; horizontal: true }
    ListView {
        id: strip
        KineticWheel { view: strip; horizontal: true }
        orientation: ListView.Horizontal
        anchors.left: parent.left
        anchors.right: tools.left
        anchors.rightMargin: Theme.gap
        height: parent.height
        spacing: Theme.gap
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width + 1
        model: tr.tabs
        currentIndex: tr.activeIndex
        highlightFollowsCurrentItem: false
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
        Accessible.role: Accessible.PageTabList
        Accessible.name: I18n.tr("terminal.tabs")
        delegate: Block {
            id: key
            required property var modelData
            required property int index
            readonly property bool on: modelData.id === tr.active
            readonly property bool showClose: (hov.hovered || key.activeFocus || key.on) && !key.editing
            property bool editing: false
            onEditingChanged: {
                tr.editing = editing
                Store.act("terminal.hold", { on: editing })
            }
            readonly property real closeW: 18
            width: Math.min(220, Math.max(72, label.implicitWidth + 2 * Theme.pad + (closeW + Theme.xs)))
            height: tr.keyH + Theme.shadowDy
            radius: Theme.rFull
            fill: on ? Theme.selected : (hov.hovered ? Theme.containerHigh : Theme.container)
            flatBorder: on ? "transparent" : Theme.outline
            pressed: tap.pressed
            activeFocusOnTab: true
            Accessible.role: Accessible.PageTab
            Accessible.name: I18n.tr("terminal.tab.a11y").replace("{n}", String(index + 1))
                .replace("{of}", String(tr.tabs.length)).replace("{title}", tr.nameOf(modelData))
            Accessible.selected: on
            Keys.onReturnPressed: Store.act("terminal.select", { tab: modelData.id })
            Keys.onSpacePressed: Store.act("terminal.select", { tab: modelData.id })
            Keys.onDeletePressed: Store.act("terminal.close_tab", { tab: modelData.id })
            Keys.onPressed: e => { if (e.key === Qt.Key_F2) { key.editing = true; e.accepted = true } }
            Text {
                id: label
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                visible: !key.editing
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.pad
                width: key.width - 2 * Theme.pad - key.closeW - Theme.xs
                elide: Text.ElideMiddle
                text: tr.nameOf(key.modelData)
                color: key.on ? Theme.fgOnSelected : Theme.fg
                font.pixelSize: Theme.fs
                font.weight: key.on ? Theme.wMedium : Font.Normal
                font.family: Theme.fam(text, Theme.families)
            }
            TextInput {
                id: edit
                visible: key.editing
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.pad
                width: key.width - 2 * Theme.pad
                clip: true
                color: key.on ? Theme.fgOnSelected : Theme.fg
                selectionColor: Qt.alpha(Theme.accent, 0.4)
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                selectByMouse: true
                onVisibleChanged: if (visible) { text = tr.nameOf(key.modelData); selectAll(); forceActiveFocus() }
                Keys.onReturnPressed: { Store.act("terminal.rename", { tab: key.modelData.id, title: text }); key.editing = false }
                Keys.onEnterPressed: { Store.act("terminal.rename", { tab: key.modelData.id, title: text }); key.editing = false }
                Keys.onEscapePressed: key.editing = false
                onActiveFocusChanged: if (!activeFocus) key.editing = false
                Accessible.name: I18n.tr("terminal.tab.rename")
            }
            // × (the current tab's, the hovered and the focused one's).
            Item {
                id: close
                visible: key.showClose
                width: key.closeW
                height: key.closeW
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Theme.xs + 2
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("terminal.tab.close")
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: closeHov.hovered ? Qt.alpha(key.on ? Theme.fgOnSelected : Theme.fg, 0.16) : "transparent"
                }
                Icon {
                    anchors.centerIn: parent
                    name: "close"
                    glyph: "×"
                    size: Theme.fs
                    color: key.on ? Theme.fgOnSelected : Theme.dim
                }
                HoverHandler { id: closeHov }
                TapHandler { onTapped: Store.act("terminal.close_tab", { tab: key.modelData.id }) }
            }
            HoverHandler { id: hov }
            MouseArea {
                id: tap
                anchors.fill: parent
                anchors.rightMargin: close.visible ? close.width + Theme.xs + 2 : 0
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onClicked: m => {
                    if (m.button === Qt.MiddleButton) Store.act("terminal.close_tab", { tab: key.modelData.id })
                    else Store.act("terminal.select", { tab: key.modelData.id })
                }
                onDoubleClicked: m => { if (m.button === Qt.LeftButton) key.editing = true }
            }
            FocusRing { parent: key.face; anchors.fill: parent; shown: key.activeFocus; corner: key.radius }
        }
    }

    // "+" and its menu, the pin.
    Row {
        id: tools
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.xs
        KeyButton {
            id: plus
            side: tr.keyH
            icon: "add"
            glyph: "+"
            a11y: I18n.tr("terminal.tab.new")
            onClicked: Store.act("terminal.new_tab", {})
            // (a right click on "+" is its menu, as on a browser's or Windows Terminal's)
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: tr.openMenu()
            }
        }
        KeyButton {
            id: more
            objectName: "terminal-plus-menu"
            side: tr.keyH
            icon: "expand_more"
            glyph: "⌄"
            primary: plusMenu.open
            a11y: I18n.tr("terminal.menu.title")
            onClicked: tr.openMenu()
            Keys.onDownPressed: tr.openMenu()
        }
        KeyButton {
            visible: tr.showPin
            side: tr.keyH
            icon: "push_pin"
            glyph: "⌖"
            primary: tr.pinned
            enabled: !tr.pinForced
            a11y: tr.pinForced ? I18n.tr("terminal.pin.forced").replace("{by}", String(tr.doc.forced.pinned))
                : (tr.pinned ? I18n.tr("terminal.pin.off") : I18n.tr("terminal.pin.on"))
            onClicked: Store.act("terminal.pin", {})
        }
    }
}
