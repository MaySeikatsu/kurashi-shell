import QtQuick
import "../core"

// Preview cards sorted into categories (W29, K53; docs/ux/looks.md "Settings"). Offers that carry a `group` (styles and
// looks: modern, inspired, retro, fiction, custom) are shown one category at a time: a row of chips, each with its count,
// only for categories that have packs; the current pack's category is open until another chip is opened. Offers without
// a group (the style "None (your own)") are plain cards in front of the categories, always shown. Offers without any
// group (palettes) are one set of cards. Keyboard: the chips are tabs — one Tab stop, Left/Right move between them,
// Return/Space open one — and Tab goes on into the cards (DecorCards' roving radio group).
Item {
    id: pc
    property var choices: []
    property var current
    property bool enabled: true
    property var looks: ({})
    property bool previewOnMove: true
    signal picked(var value)
    signal previewed(var value)
    signal cancelled()

    // The order the categories show in (K53's list); a category the daemon adds later goes after them.
    readonly property var order: ["modern", "inspired", "retro", "fiction", "custom"]
    readonly property var lead: pc.choices.filter(function (c) { return !c.group })
    readonly property var categories: {
        var counts = {}
        pc.choices.forEach(function (c) { if (c.group) counts[c.group] = (counts[c.group] || 0) + 1 })
        var names = Object.keys(counts).sort(function (a, b) {
            var ia = pc.order.indexOf(a), ib = pc.order.indexOf(b)
            return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || a.localeCompare(b)
        })
        return names.map(function (n) { return { id: n, count: counts[n] } })
    }
    readonly property bool grouped: pc.categories.length > 0
    readonly property string currentGroup: {
        for (var i = 0; i < pc.choices.length; i++)
            if (JSON.stringify(pc.choices[i].value) === JSON.stringify(pc.current)) return pc.choices[i].group || ""
        return ""
    }
    // The open category: the one a chip opened, else the current pack's, else the first.
    property string opened: ""
    readonly property string openCat: {
        var ids = pc.categories.map(function (c) { return c.id })
        if (pc.opened !== "" && ids.indexOf(pc.opened) >= 0) return pc.opened
        if (ids.indexOf(pc.currentGroup) >= 0) return pc.currentGroup
        return ids.length ? ids[0] : ""
    }
    readonly property var shown: pc.grouped ? pc.choices.filter(function (c) { return c.group === pc.openCat }) : pc.choices
    function open(id) { pc.opened = id }
    // The test hook and the keyboard: the chips as ids, in order.
    function categoryIds() { return pc.categories.map(function (c) { return c.id }).join(",") }

    implicitWidth: 600
    implicitHeight: body.implicitHeight

    Row {
        id: body
        width: pc.width
        spacing: Theme.gap * 2
        // The plain cards in front of the categories (None (your own)).
        DecorCards {
            id: leadCards
            visible: pc.grouped && pc.lead.length > 0
            width: visible ? 156 * pc.lead.length + Theme.gap * (pc.lead.length - 1) : 0
            objectName: pc.objectName + ":lead"
            choices: pc.grouped ? pc.lead : []
            looks: pc.looks
            current: pc.current
            enabled: pc.enabled
            previewOnMove: pc.previewOnMove
            onPicked: v => pc.picked(v)
            onPreviewed: v => pc.previewed(v)
            onCancelled: pc.cancelled()
        }
        Column {
            width: pc.width - (leadCards.visible ? leadCards.width + body.spacing : 0)
            spacing: Theme.gap * 1.5
            Flow {
                id: chips
                visible: pc.grouped
                width: parent.width
                spacing: Theme.gap
                Accessible.role: Accessible.PageTabList
                Accessible.name: I18n.tr("settings.appearance.categories")
                Repeater {
                    id: chipRep
                    model: pc.categories
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        required property int index
                        readonly property bool on: modelData.id === pc.openCat
                        readonly property string name: I18n.tr("appearance.category." + modelData.id)
                        objectName: "category:" + modelData.id
                        width: lbl.implicitWidth + Theme.pad * 2
                        height: Theme.controlH
                        radius: height / 2
                        color: chip.on ? Theme.selected : (hov.hovered ? Theme.containerHigh : "transparent")
                        border.width: chip.on ? (Theme.outlineW > 0 ? Theme.outlineW : 0) : 1
                        border.color: chip.on ? Theme.line : Theme.outline
                        opacity: pc.enabled ? 1 : 0.5
                        activeFocusOnTab: chip.on
                        function step(d) {
                            var c = chipRep.itemAt(chip.index + d)
                            if (c) c.forceActiveFocus()
                        }
                        Keys.onLeftPressed: event => { chip.step(-1); event.accepted = true }
                        Keys.onRightPressed: event => { chip.step(1); event.accepted = true }
                        Keys.onReturnPressed: event => { pc.open(modelData.id); event.accepted = true }
                        Keys.onEnterPressed: event => { pc.open(modelData.id); event.accepted = true }
                        Keys.onSpacePressed: event => { pc.open(modelData.id); event.accepted = true }
                        Accessible.role: Accessible.PageTab
                        Accessible.name: I18n.fmt("settings.appearance.category_count", { name: chip.name, n: modelData.count })
                        Accessible.selected: chip.on
                        Text {
                            id: lbl
                            anchors.centerIn: parent
                            color: chip.on ? Theme.fgOnSelected : Theme.fg
                            font.pixelSize: Theme.fs
                            font.weight: chip.on ? Theme.wBold : Theme.wMedium
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.fmt("settings.appearance.category_count", { name: chip.name, n: modelData.count })
                        }
                        HoverHandler { id: hov }
                        MouseArea {
                            anchors.fill: parent
                            enabled: pc.enabled
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pc.open(modelData.id)
                        }
                        FocusRing {
                            anchors.fill: parent
                            shown: chip.activeFocus
                            corner: chip.radius
                        }
                    }
                }
            }
            // Only the open category's cards exist (the others are not built: Ma).
            DecorCards {
                width: parent.width
                objectName: pc.objectName
                choices: pc.shown
                looks: pc.looks
                current: pc.current
                enabled: pc.enabled
                previewOnMove: pc.previewOnMove
                onPicked: v => pc.picked(v)
                onPreviewed: v => pc.previewed(v)
                onCancelled: pc.cancelled()
            }
        }
    }
}
