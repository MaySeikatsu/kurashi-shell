import QtQuick
import "../core"
import "groups.js" as G

// A small bar preview (W80, I508; docs/ux/groups.md "Round two", "The bar preview"): the selected edge's zones as the bar
// draws them on the chosen output (or every output), a chip per module and a framed chip per named group. The list's drops
// work here too, within a zone: a chip onto a chip groups them, onto a group joins it, a group onto a group asks first, a
// member dropped on its zone's ground leaves. Keyboard: Tab walks the chips; Ctrl+Left/Right drops the focused chip onto
// its neighbour, Ctrl+Down takes a member out. Each gesture is one apply of `layout.groups` and the zone's list; the chips
// show the daemon's values only (Shōjiki). A forced zone list is inert (its row in the list says why).
Column {
    id: bp
    property string output: ""
    property string edge: "top"
    readonly property var zoneIds: ["start", "center", "end"]
    readonly property var groups: { var g = Store.valueOf("layout.groups"); return Array.isArray(g) ? g : [] }
    function keyOf(z) { return "edges." + bp.edge + "." + z }
    function listOf(z) { var v = Store.valueOf(keyOf(z), bp.output); return Array.isArray(v) ? v : [] }
    function editable(z) { var p = Store.prov(keyOf(z), bp.output); return !(p && p.forced_by) }
    function groupName(id) { var r = G.recordOf(bp.groups, id); return r && r.name ? r.name : id }
    // The value a drag carries and its zone; a merge waiting for its confirm {zone, from, into}.
    property string dragging: ""
    property string dragZone: ""
    property bool dragActive: false
    property var askMerge: null

    function send(z, res) { if (res) Store.apply(G.ops(res, keyOf(z), bp.output)) }
    function dropOnto(z, a, b) {
        if (a === b || !editable(z)) return
        var list = listOf(z)
        var gb = G.isGroup(b) ? G.idOf(b) : G.groupOf(list, bp.groups, b)
        if (G.isGroup(a) && gb !== "" && G.idOf(a) !== gb) { askMerge = { zone: z, from: G.idOf(a), into: gb }; return }
        if (gb !== "" && gb === G.groupOf(list, bp.groups, a)) return
        send(z, G.dropOnto(list, bp.groups, a, b))
    }
    function leave(z, m) { if (editable(z)) send(z, G.leave(listOf(z), bp.groups, m)) }
    function confirmMerge() {
        var m = askMerge
        askMerge = null
        if (m) send(m.zone, G.merge(listOf(m.zone), bp.groups, m.from, m.into))
    }
    function startDrag(z, v, name, area, mouse) {
        var p = dragLayer.mapFromItem(area, mouse.x - 12, mouse.y - proxy.height / 2)
        proxy.x = p.x
        proxy.y = p.y
        proxy.text = name
        bp.dragging = v
        bp.dragZone = z
    }
    function endDrag() {
        if (proxy.Drag.active) proxy.Drag.drop()
        bp.dragActive = false
        bp.dragging = ""
        bp.dragZone = ""
    }

    spacing: Theme.gap / 2
    objectName: "barpreview"
    Accessible.role: Accessible.Grouping
    Accessible.name: I18n.tr("settings.groups.preview")

    Text {
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.bold: true
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("settings.groups.preview")
    }
    Text {
        width: bp.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fs - 1
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("settings.groups.preview_help")
    }
    // The bar: three zones, start at the left, centre in the middle, end at the right.
    Rectangle {
        id: strip
        width: bp.width
        height: Theme.controlH + 12
        radius: Theme.rSm
        color: Theme.container
        border.width: 1
        border.color: Theme.outline
        Repeater {
            model: bp.zoneIds
            delegate: Item {
                id: zone
                required property string modelData
                required property int index
                readonly property var list: bp.listOf(zone.modelData)
                readonly property bool live: bp.editable(zone.modelData)
                height: strip.height
                width: chips.implicitWidth + 8
                x: zone.index === 0 ? 4 : (zone.index === 1 ? (strip.width - width) / 2 : strip.width - width - 4)
                opacity: zone.live ? 1 : 0.5
                // A member dropped on its zone's ground leaves its group.
                DropArea {
                    anchors.fill: parent
                    keys: ["kurashi-preview"]
                    enabled: bp.dragZone === zone.modelData && G.groupOf(zone.list, bp.groups, bp.dragging) !== ""
                    onDropped: bp.leave(zone.modelData, bp.dragging)
                }
                Row {
                    id: chips
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        visible: zone.list.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.dim
                        font.pixelSize: Theme.fs - 2
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("settings.groups.zone." + zone.modelData) + ": " + I18n.tr("settings.groups.zone_empty")
                    }
                    Repeater {
                        model: zone.list
                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            required property int index
                            readonly property bool isGroup: G.isGroup(chip.modelData)
                            readonly property var members: chip.isGroup ? G.membersOf(G.recordOf(bp.groups, G.idOf(chip.modelData))) : []
                            readonly property string name: chip.isGroup ? bp.groupName(G.idOf(chip.modelData)) : Store.moduleName(chip.modelData)
                            anchors.verticalCenter: parent.verticalCenter
                            height: Theme.controlH - 4
                            width: chip.isGroup ? inner.implicitWidth + 8 : label.implicitWidth + 16
                            radius: Theme.rSm
                            color: cdrop.containsDrag ? Theme.containerHigh : (chip.isGroup ? "transparent" : Theme.containerHigh)
                            border.width: chip.isGroup || cdrop.containsDrag || chip.activeFocus ? 2 : 1
                            border.color: cdrop.containsDrag || chip.activeFocus ? Theme.accent : Theme.outline
                            activeFocusOnTab: zone.live
                            objectName: "previewchip:" + chip.modelData
                            Accessible.role: Accessible.ListItem
                            Accessible.name: chip.isGroup
                                ? I18n.fmt("settings.groups.a11y_group", { name: chip.name, n: chip.members.length }) : chip.name
                            Keys.onPressed: event => {
                                if (!(event.modifiers & Qt.ControlModifier)) return
                                if (event.key === Qt.Key_Right || event.key === Qt.Key_Left) {
                                    var j = chip.index + (event.key === Qt.Key_Right ? 1 : -1)
                                    if (j >= 0 && j < zone.list.length) bp.dropOnto(zone.modelData, chip.modelData, zone.list[j])
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Return && bp.askMerge) {
                                    bp.confirmMerge()
                                    event.accepted = true
                                }
                            }
                            Keys.onEscapePressed: event => { if (bp.askMerge) { bp.askMerge = null; event.accepted = true } else event.accepted = false }
                            DropArea {
                                id: cdrop
                                anchors.fill: parent
                                keys: ["kurashi-preview"]
                                enabled: bp.dragZone === zone.modelData && bp.dragging !== chip.modelData
                                    && chip.members.indexOf(bp.dragging) < 0
                                onDropped: bp.dropOnto(zone.modelData, bp.dragging, chip.modelData)
                            }
                            MouseArea {
                                id: carea
                                anchors.fill: parent
                                enabled: zone.live
                                preventStealing: true
                                cursorShape: enabled ? Qt.OpenHandCursor : Qt.ArrowCursor
                                drag.target: proxy
                                drag.threshold: 6
                                readonly property bool dragOn: drag.active
                                onDragOnChanged: bp.dragActive = dragOn
                                onPressed: mouse => bp.startDrag(zone.modelData, chip.modelData, chip.name, carea, mouse)
                                onReleased: bp.endDrag()
                            }
                            Text {
                                id: label
                                visible: !chip.isGroup
                                anchors.centerIn: parent
                                color: Theme.fg
                                font.pixelSize: Theme.fs - 2
                                font.family: Theme.fam(text, Theme.families)
                                text: chip.isGroup ? "" : chip.name
                            }
                            // A group: its members side by side inside the frame, each draggable out (and a drop target).
                            Row {
                                id: inner
                                visible: chip.isGroup
                                anchors.centerIn: parent
                                spacing: 2
                                Repeater {
                                    model: chip.members
                                    delegate: Rectangle {
                                        id: mchip
                                        required property string modelData
                                        height: Theme.controlH - 12
                                        width: mlabel.implicitWidth + 12
                                        radius: Theme.rSm
                                        color: mdrop2.containsDrag ? Theme.container : Theme.containerHigh
                                        border.width: mchip.activeFocus ? 2 : 0
                                        border.color: Theme.accent
                                        activeFocusOnTab: zone.live
                                        objectName: "previewmember:" + mchip.modelData
                                        Accessible.role: Accessible.ListItem
                                        Accessible.name: I18n.fmt("settings.groups.a11y_member", { item: mlabel.text, name: chip.name })
                                        Keys.onPressed: event => {
                                            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Down) {
                                                bp.leave(zone.modelData, mchip.modelData)
                                                event.accepted = true
                                            }
                                        }
                                        DropArea {
                                            id: mdrop2
                                            anchors.fill: parent
                                            keys: ["kurashi-preview"]
                                            enabled: bp.dragZone === zone.modelData && bp.dragging !== mchip.modelData
                                                && chip.members.indexOf(bp.dragging) < 0 && bp.dragging !== chip.modelData
                                            onDropped: bp.dropOnto(zone.modelData, bp.dragging, mchip.modelData)
                                        }
                                        MouseArea {
                                            id: marea
                                            anchors.fill: parent
                                            enabled: zone.live
                                            preventStealing: true
                                            cursorShape: enabled ? Qt.OpenHandCursor : Qt.ArrowCursor
                                            drag.target: proxy
                                            drag.threshold: 6
                                            readonly property bool dragOn: drag.active
                                            onDragOnChanged: bp.dragActive = dragOn
                                            onPressed: mouse => bp.startDrag(zone.modelData, mchip.modelData, mlabel.text, marea, mouse)
                                            onReleased: bp.endDrag()
                                        }
                                        Text {
                                            id: mlabel
                                            anchors.centerIn: parent
                                            color: Theme.fg
                                            font.pixelSize: Theme.fs - 2
                                            font.family: Theme.fam(text, Theme.families)
                                            text: Store.moduleName(mchip.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    // A group dropped onto a group: the confirm.
    Row {
        visible: bp.askMerge !== null
        spacing: Theme.gap
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: bp.askMerge ? I18n.fmt("settings.groups.merge_ask",
                { from: bp.groupName(bp.askMerge.from), into: bp.groupName(bp.askMerge.into) }) : ""
        }
        Button {
            objectName: "previewmerge"
            label: I18n.tr("settings.groups.merge")
            primary: true
            onClicked: bp.confirmMerge()
        }
        Button {
            label: I18n.tr("settings.groups.cancel")
            onClicked: bp.askMerge = null
        }
    }
    Item {
        id: dragLayer
        width: bp.width
        height: 0
        z: 10
        Rectangle {
            id: proxy
            property string text: ""
            visible: bp.dragging !== "" && bp.dragActive
            Drag.active: bp.dragActive
            Drag.keys: ["kurashi-preview"]
            Drag.hotSpot.x: 12
            Drag.hotSpot.y: height / 2
            width: plabel.implicitWidth + 16
            height: Theme.controlH - 4
            radius: Theme.rSm
            color: Theme.containerHigh
            border.width: 1
            border.color: Theme.accent
            opacity: 0.92
            Text {
                id: plabel
                anchors.centerIn: parent
                color: Theme.fg
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: proxy.text
            }
        }
    }
}
