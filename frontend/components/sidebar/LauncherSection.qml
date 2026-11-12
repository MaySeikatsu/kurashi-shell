import QtQuick
import Quickshell
import "../../core"
import ".."

// The launcher as a sidebar section (session 30, I501, docs/ux/groups.md; the user: "add opening … the launcher in the
// sidebar"): the launcher's own search (`query launcher` — apps, `>` commands, `=` sums, `:` emoji, `?` keys, as the
// launcher has them) in a card that stays in the column: a field and the best rows under it. Return or a click runs the
// row (`launcher.launch`); a command or a Settings link closes the sidebar first, as the launcher closes itself. An error
// stays under the field with its reason (Shōjiki). Ma: nothing is asked until something is typed; the empty field shows
// nothing (the sidebar is not a second app grid).
Card {
    id: ls
    property var rows: []
    property string err: ""
    property int sel: 0
    readonly property int maxRows: 8
    function run(q) {
        if (q === "") { rows = []; err = ""; return }
        Store.query("launcher", q, function (items, e) {
            if (q !== field.text) return
            ls.rows = (items || []).filter(function (r) { return r.kind !== "keygroup" && !!r.id }).slice(0, ls.maxRows)
            ls.sel = 0
            ls.err = e ? String(e.message || e.code || e) : ""
        })
    }
    function launch(i) {
        if (i < 0 || i >= rows.length) return
        var id = String(rows[i].id)
        var closeFirst = id.indexOf("cmd:") === 0 || id.indexOf("settings:") === 0
        if (closeFirst) { Store.act("sidebar.close", {}, function () { Store.act("launcher.launch", { id: id }) }); return }
        Store.act("launcher.launch", { id: id }, function (done, e) {
            if (e) { ls.err = String(e.message || e.code || e); return }
            field.text = ""
        })
    }
    Column {
        width: ls.width - 2 * Theme.pad
        spacing: Theme.gap
        Rectangle {
            width: parent.width
            height: 38
            radius: height / 2
            color: Theme.containerHigh
            border.width: field.activeFocus ? 2 : 1
            border.color: field.activeFocus ? Theme.accent : Theme.outline
            Icon {
                id: glass
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                glyph: "⌕"
                color: Theme.dim
            }
            TextInput {
                id: field
                anchors { left: glass.right; leftMargin: 8; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                color: Theme.fg
                selectionColor: Theme.accent
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                clip: true
                onTextChanged: ls.run(text)
                Keys.onDownPressed: ls.sel = Math.min(ls.rows.length - 1, ls.sel + 1)
                Keys.onUpPressed: ls.sel = Math.max(0, ls.sel - 1)
                Keys.onReturnPressed: ls.launch(ls.sel)
                Keys.onEnterPressed: ls.launch(ls.sel)
                Keys.onEscapePressed: event => { if (text !== "") { text = ""; event.accepted = true } else event.accepted = false }
                Accessible.role: Accessible.EditableText
                Accessible.name: I18n.tr("launcher.placeholder")
                Text {
                    visible: field.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("launcher.placeholder")
                    color: Theme.dim
                    font: field.font
                }
            }
        }
        Text {
            visible: ls.err !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: ls.err
            color: Theme.error
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }
        Repeater {
            model: ls.rows
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: parent.width
                height: 40
                Accessible.role: Accessible.Button
                Accessible.name: String(modelData.name || "")
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.rSm
                    color: Theme.selected
                    visible: row.index === ls.sel || hov.hovered
                    opacity: row.index === ls.sel ? 0.8 : 0.45
                }
                Image {
                    id: img
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    sourceSize: Qt.size(52, 52)
                    asynchronous: true
                    source: row.modelData.icon_path ? "file://" + row.modelData.icon_path
                        : (row.modelData.icon && row.modelData.kind !== "command" ? Quickshell.iconPath(row.modelData.icon, true) : "")
                    visible: status === Image.Ready
                }
                Icon {
                    visible: !img.visible
                    anchors.centerIn: img
                    name: String(row.modelData.icon || "apps")
                    glyph: String(row.modelData.glyph || "•")
                    color: Theme.dim
                }
                Column {
                    anchors { left: img.right; leftMargin: 10; right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: String(row.modelData.name || "")
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.weight: row.index === ls.sel ? Theme.wBold : Font.Normal
                        font.family: Theme.fam(text, Theme.families)
                    }
                    Text {
                        visible: text !== ""
                        width: parent.width
                        elide: Text.ElideRight
                        text: String(row.modelData.generic || "")
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                    }
                }
                HoverHandler { id: hov }
                TapHandler { onTapped: { ls.sel = row.index; ls.launch(row.index) } }
            }
        }
    }
}
