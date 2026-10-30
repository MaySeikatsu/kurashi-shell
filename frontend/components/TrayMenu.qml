import QtQuick
import Quickshell
import "../core"
import "decor"

// The menu of one tray item (K23): the tree kurashi-tray built, drawn in place. Submenus open inline,
// indented. A pure view: a chosen entry is signalled (`chosen`) and the Stage sends tray.menu_event.
// Keys come from the Stage card, its one keyboard holder: Up/Down move over the enabled entries,
// Right/Left open and close a submenu, Enter chooses (or opens a submenu). Esc is the Stage's.
Item {
    id: menu
    // The look's menu metrics (W53, row 591): today's where it leaves them.
    MenuStyle { id: ms }

    // The tree as tray.menu returned it; null while it loads.
    property var tree: null
    // A translated line for a failed tray.menu (the Stage sets it).
    property string errText: ""
    // Index into `rows` the keys point at; -1 until the first key.
    property int cursor: -1
    // Submenu entry id -> true while it is open.
    property var expanded: ({})

    signal chosen(int item)

    // Entries on screen, depth first: a submenu's children follow it only while it is open.
    readonly property var rows: flatten()
    function flatten() {
        var out = []
        var walk = function (list, depth) {
            for (var i = 0; i < list.length; i++) {
                out.push({ entry: list[i], depth: depth })
                if (list[i].children && expanded[list[i].id] === true) walk(list[i].children, depth + 1)
            }
        }
        walk((tree && tree.children) || [], 0)
        return out
    }
    function selectable(i) {
        var e = rows[i].entry
        return !e.separator && e.enabled !== false
    }
    function isOpen(id) { return expanded[id] === true }
    function indexOf(id) {
        for (var i = 0; i < rows.length; i++) if (rows[i].entry.id === id) return i
        return -1
    }

    // Moves the cursor one enabled entry in `dir`, wrapping; the first key starts at the near end.
    function step(dir) {
        var n = rows.length
        if (n === 0) return
        var i = cursor < 0 ? (dir > 0 ? n - 1 : 0) : cursor
        for (var k = 0; k < n; k++) {
            i = (i + dir + n) % n
            if (selectable(i)) { cursor = i; return }
        }
    }
    function setOpen(id, on) {
        var x = Object.assign({}, expanded)
        x[id] = on
        expanded = x
        var i = indexOf(id)
        if (i >= 0) cursor = i
    }
    function activate(i) {
        if (i < 0 || i >= rows.length || !selectable(i)) return
        var e = rows[i].entry
        if (e.children) setOpen(e.id, !isOpen(e.id))
        else chosen(e.id)
    }

    // Keys from the Stage card. Returns false for keys the menu does not use.
    function handleKey(key) {
        if (key === Qt.Key_Down || key === Qt.Key_Tab) step(1)
        else if (key === Qt.Key_Up || key === Qt.Key_Backtab) step(-1)
        else if (key === Qt.Key_Right || key === Qt.Key_Left) {
            var i = cursor
            if (i < 0 || !rows[i].entry.children) return false
            setOpen(rows[i].entry.id, key === Qt.Key_Right)
        }
        else if (key === Qt.Key_Return || key === Qt.Key_Enter) activate(cursor)
        else return false
        return true
    }

    implicitHeight: body.implicitHeight

    Column {
        id: body
        width: menu.width
        spacing: 2

        Repeater {
            model: menu.rows
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property var e: modelData.entry
                readonly property bool sep: e.separator === true
                readonly property bool live: menu.selectable(index)
                readonly property bool current: menu.cursor === index && live
                // Depth shifts the row; the mark and icon columns keep labels aligned across rows.
                readonly property int indent: Theme.pad + modelData.depth * (Theme.pad + 4)

                width: body.width
                height: sep ? 9 : ms.rowH(Theme.controlH)
                Accessible.role: Accessible.MenuItem
                Accessible.name: e.label ?? ""
                Accessible.checkable: e.toggle !== undefined
                Accessible.checked: e.checked === true

                // The look's row face (W53, row 591); today's line and capsule below while the look leaves them.
                MenuRowFace {
                    id: face
                    anchors.fill: parent
                    highlighted: row.current
                    separator: row.sep
                    enabled: row.live
                    checked: row.e.checked === true
                }
                Rectangle {
                    visible: row.sep && face.ownSeparator
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: Theme.pad
                        rightMargin: Theme.pad
                    }
                    height: 1
                    color: Theme.outline
                }

                Rectangle {
                    visible: !row.sep && face.ownHighlight
                    anchors.fill: parent
                    radius: ms.radius(Theme.rSm)
                    color: row.current ? Theme.containerHigh : "transparent"
                    border.width: row.current ? 1 : 0
                    border.color: Theme.outline
                }

                // Checkmark, or a radio dot for a radio entry: the state is the glyph, not colour alone.
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    visible: !row.sep
                    x: row.indent
                    width: 16
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    color: face.ink(row.live ? Theme.fg : Theme.dim)
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: row.e.toggle === "checkmark" ? (row.e.checked === true ? "✓" : "")
                        : row.e.toggle === "radio" ? (row.e.checked === true ? "●" : "○") : ""
                }

                Image {
                    visible: !row.sep && row.e.icon_name !== undefined && Quickshell.hasThemeIcon(row.e.icon_name)
                    x: row.indent + 22
                    width: 16
                    height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    sourceSize: Qt.size(32, 32)
                    source: visible ? Quickshell.iconPath(row.e.icon_name) : ""
                }

                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    visible: !row.sep
                    x: row.indent + 44
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, body.width - x - 28)
                    elide: Text.ElideRight
                    color: face.ink(row.live ? Theme.fg : Theme.dim)
                    opacity: row.e.enabled === false ? 0.5 : 1
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: row.e.label ?? ""
                }

                // A submenu's chevron, turned down while it is open.
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    visible: !row.sep && row.e.children !== undefined
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.pad
                    anchors.verticalCenter: parent.verticalCenter
                    rotation: menu.isOpen(row.e.id) ? 90 : 0
                    color: face.ink(row.live ? Theme.fg : Theme.dim)
                    font.pixelSize: Theme.fs + 2
                    text: "›"
                }

                HoverHandler {
                    enabled: !row.sep && row.live
                    onHoveredChanged: if (hovered) menu.cursor = row.index
                }
                TapHandler {
                    enabled: !row.sep && row.live
                    onTapped: menu.activate(row.index)
                }
            }
        }

        // Loading, an item with no menu, or the failure of tray.menu; nothing otherwise.
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            width: body.width
            visible: text !== ""
            wrapMode: Text.WordWrap
            color: menu.errText !== "" ? Theme.error : Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: menu.errText !== "" ? menu.errText
                : menu.tree === null ? I18n.tr("frontend.tray.loading")
                : menu.rows.length === 0 ? I18n.tr("frontend.tray.empty") : ""
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            width: body.width
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("frontend.tray.hint")
        }
    }
}
