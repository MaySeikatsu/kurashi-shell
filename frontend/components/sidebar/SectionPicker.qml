import QtQuick
import "../../core"
import ".."

// What a sidebar shows, chosen in place (session 30, I500 c, docs/ux/groups.md "'+' in place"; the user: a "+" to attach
// other content to the bar or remove it). A sheet over the column listing everything a sidebar can show — the daemon's
// offers for `sidebar.<side>.sections` (the core sections, every mod panel, the named groups) — each with a check mark;
// a tick adds it at the end, an untick takes it out: one apply each, so `kurashi undo` steps back. A list the configuration
// forces is shown inert with its reason (Shōjiki). Keyboard: Up/Down, Space or Return toggles, Esc closes.
// Ma: `schema.settings` is watched only while the sheet is open.
FocusScope {
    id: sp
    property string side: "left"
    property bool open: false
    signal closed()
    readonly property string key: "sidebar." + side + ".sections"
    visible: open
    Watch { doc: "schema.settings"; active: sp.open }
    readonly property var row: {
        var s = open ? Store.docs["schema.settings"] : null
        if (!s || !s.pages) return null
        for (var i = 0; i < s.pages.length; i++)
            for (var j = 0; j < s.pages[i].sections.length; j++) {
                var rs = s.pages[i].sections[j].rows
                for (var k = 0; k < rs.length; k++) if (rs[k].key === sp.key) return rs[k]
            }
        return null
    }
    readonly property var entry: ((Store.docs["config"] || ({})).values || ({}))[key] || null
    readonly property var current: entry && Array.isArray(entry.value) ? entry.value : []
    readonly property string forcedBy: entry && entry.forced_by ? String(entry.forced_by) : ""
    readonly property var choices: row && Array.isArray(row.choices) ? row.choices : []
    function toggle(v) {
        if (forcedBy !== "") return
        var list = current.slice(), i = list.indexOf(v)
        if (i >= 0) list.splice(i, 1)
        else list.push(v)
        Store.apply([{ set: key, value: list }])
    }
    function close() { open = false; closed() }
    onOpenChanged: if (open) { list.currentIndex = 0; Qt.callLater(function () { list.forceActiveFocus() }) }
    Keys.onEscapePressed: close()

    Block {
        anchors.fill: parent
        radius: Theme.rLg
        fill: Theme.panel
        flatBorder: Theme.surfaceHair
    }
    Text {
        id: head
        x: Theme.pad
        y: Theme.pad
        width: parent.width - 2 * Theme.pad - done.width
        text: I18n.tr("sidebar.sections.title")
        color: Theme.fg
        font.pixelSize: Theme.fsTitle
        font.weight: Theme.wBold
        font.family: Theme.fam(text, Theme.families)
        elide: Text.ElideRight
        TextFx { title: true }
    }
    IconButton {
        id: done
        anchors { right: parent.right; rightMargin: Theme.gap; verticalCenter: head.verticalCenter }
        icon: "close"
        glyph: "×"
        a11y: I18n.tr("sidebar.sections.close")
        onClicked: sp.close()
    }
    Text {
        id: why
        visible: sp.forcedBy !== ""
        x: Theme.pad
        y: head.y + head.height + Theme.xs
        width: parent.width - 2 * Theme.pad
        wrapMode: Text.WordWrap
        text: I18n.tr("sidebar.sections.forced").replace("{by}", sp.forcedBy)
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
    }
    ScrollEdge { view: list }
    ListView {
        id: list
        KineticWheel { view: list }
        x: Theme.gap
        y: (why.visible ? why.y + why.height : head.y + head.height) + Theme.gap
        width: parent.width - 2 * Theme.gap
        height: parent.height - y - Theme.gap
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: sp.choices
        focus: true
        keyNavigationEnabled: true
        highlightMoveDuration: 0
        Accessible.role: Accessible.List
        Accessible.name: I18n.tr("sidebar.sections.title")
        Keys.onSpacePressed: if (currentItem) sp.toggle(currentItem.value)
        Keys.onReturnPressed: if (currentItem) sp.toggle(currentItem.value)
        delegate: Item {
            id: rowItem
            required property var modelData
            required property int index
            readonly property string value: String(modelData.value)
            readonly property bool on: sp.current.indexOf(value) >= 0
            readonly property bool usable: modelData.enabled !== false && sp.forcedBy === ""
            width: list.width
            height: 34
            opacity: usable ? 1 : Theme.staleOpacity
            Accessible.role: Accessible.CheckBox
            Accessible.name: label.text
            Accessible.checkable: true
            Accessible.checked: on
            Rectangle {
                anchors.fill: parent
                radius: Theme.rSm
                color: Theme.selected
                visible: rowItem.ListView.isCurrentItem && list.activeFocus || hover.hovered
                opacity: 0.6
            }
            Icon {
                id: mark
                x: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                name: rowItem.on ? "check_box" : "check_box_outline_blank"
                glyph: rowItem.on ? "☑" : "☐"
                filled: rowItem.on
                color: rowItem.on ? Theme.accent : Theme.dim
            }
            Text {
                id: label
                anchors { left: mark.right; leftMargin: Theme.gap; right: parent.right; rightMargin: Theme.gap
                          verticalCenter: parent.verticalCenter }
                text: I18n.tr(String(rowItem.modelData.label || rowItem.value))
                color: Theme.fg
                elide: Text.ElideRight
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
            }
            HoverHandler { id: hover }
            TapHandler { onTapped: { list.currentIndex = rowItem.index; if (rowItem.usable) sp.toggle(rowItem.value) } }
        }
    }
}
