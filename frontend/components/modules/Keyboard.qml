import QtQuick
import "../../core"

// Module `keyboard` (K47): the keyboard layout's short name (svc.keyboard), present only while the compositor names more
// than one layout; a click switches to the next (`keyboard.next`). In a column the chip is the column's width less a margin
// and the name is cut to three letters; the full name is the accessible one (W36, I131).
ModuleBase {
    id: m
    Watch { doc: "svc.keyboard"; active: m.live }
    readonly property var d: Store.docs["svc.keyboard"] || ({})
    readonly property var layouts: d.layouts || []
    readonly property var cur: layouts.length > 0 ? layouts[Math.max(0, Math.min(layouts.length - 1, Number(d.current || 0)))] : null
    present: layouts.length > 1
    width: vertical ? thickness - 8 : kbText.implicitWidth + 2 * Theme.xs
    height: thickness - 12
    slotHeights: present ? [height] : []
    Accessible.role: Accessible.Button
    Accessible.name: I18n.tr("power.bar.layout").replace("{name}", m.cur ? String(m.cur.name) : "")
    a11yName: Accessible.name
    function activate() { Store.act("keyboard.next") }
    function geo() { return [["layout", m]] }
    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        color: kbHover.hovered ? Theme.containerHigh : "transparent"
    }
    Text {
        id: kbText
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        anchors.centerIn: parent
        color: Theme.fg
        font.pixelSize: Theme.fsCaption
        font.weight: Theme.wBold
        font.family: Theme.fam(text, Theme.families)
        text: m.cur ? String(m.cur.short).toUpperCase().substring(0, m.vertical ? 3 : 8) : ""
    }
    HoverHandler { id: kbHover }
    TapHandler { onTapped: Store.act("keyboard.next") }
}
