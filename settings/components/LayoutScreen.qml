import QtQuick
import "../core"

// Settings › Layout, the screen at the top (K71; docs/ux/layout.md "Design" and "Keyboard + a11y", docs/ux/edge-modules.md
// "Placement"). The four edges drawn as a screen: each strip is a toggle for its bar (checked = a bar stands there), named
// and worded ("Bar" / "No bar"), not coloured alone. A radio group picks the edge whose section shows below. The selected
// edge's bar can move to a free edge (`layout.bar.move`: one change, its zones go with it, so the bar is never emptied).
// What no edge shows (`unplaced`, K72) is offered back to a zone of this output. `output` is the picker's ("" = all
// outputs), `edge` the page's selection; the layout document is watched only while this card is shown (Ma).
SectionCard {
    id: screen
    property string output: ""
    property string edge: "top"
    signal edgePicked(string edge)
    // The last move the daemon refused, as its text (a strip's toggle reports a refusal at its row instead).
    property string moveError: ""

    readonly property var edges: ["top", "bottom", "left", "right"]
    title: I18n.tr("settings.layout.screen")
    icon: "view_quilt"
    Component.onCompleted: Store.watch("runtime.layout")
    Component.onDestruction: Store.unwatch("runtime.layout")

    // Whether an edge has a bar on the output (the value in effect).
    function barOn(e) {
        Store.config
        return Store.valueOf("edges." + e + ".bar", screen.output) === true
    }
    // A strip's click or Space: the edge's bar is switched. The daemon answers with the change or a refusal.
    function toggleBar(e) {
        if (!Store.live) return
        Store.setValue("edges." + e + ".bar", !screen.barOn(e), screen.output)
    }
    // The radio group and a move both name the edge the page shows below.
    function pick(e) { screen.edgePicked(e) }
    // Moves the selected edge's bar to a free edge. On success the page follows the bar to its new edge.
    function moveBar(to) {
        const args = { from: screen.edge, to: to }
        if (screen.output !== "") args.output = screen.output
        screen.moveError = ""
        Store.act("layout.bar.move", args, function (m) {
            if (m.t === "done") { screen.pick(to); return }
            screen.moveError = Store.actError(m, "settings.layout.move_failed")
        })
    }
    // The edges a bar can move to: those with no bar on the output.
    function moveChoices() {
        Store.config
        return Store.freeEdges(screen.output).map(function (e) {
            return { value: e, label: "settings.layout.edge_name." + e }
        })
    }
    // The zones a module can be added to: each edge's start, centre and end.
    function zoneChoices() {
        const out = []
        screen.edges.forEach(function (e) {
            ["start", "center", "end"].forEach(function (z) {
                out.push({ value: "edges." + e + "." + z,
                           label: I18n.fmt("settings.layout.zone_of", { edge: I18n.tr("settings.layout.edge_name." + e),
                                                                        zone: I18n.tr("settings.layout.zone." + z) }) })
            })
        })
        return out
    }
    // An unplaced module goes to the end of the zone's list, as that list is in effect.
    function addTo(id, key) {
        const cur = Store.valueOf(key, screen.output)
        const list = Array.isArray(cur) ? cur : []
        if (list.indexOf(id) >= 0) return
        Store.setValue(key, list.concat([id]), screen.output)
    }

    Column {
        width: parent.width
        spacing: Theme.gap

        // --- the screen ------------------------------------------------------------------------------------------------
        Item {
            id: stage
            width: Math.min(screen.width, 320)
            height: 176
            readonly property int band: 40   // the top and bottom strips
            readonly property int side: 72   // the left and right strips

            Rectangle {
                anchors.fill: parent
                radius: Theme.rSm
                color: Theme.containerHigh
                border.width: 1
                border.color: Theme.outline
            }
            Repeater {
                model: screen.edges
                delegate: Rectangle {
                    id: strip
                    required property string modelData
                    readonly property string e: modelData
                    readonly property bool horizontal: e === "top" || e === "bottom"
                    readonly property bool on: screen.barOn(e)
                    readonly property bool selected: screen.edge === e
                    objectName: "edge:" + e
                    x: e === "right" ? stage.width - stage.side : 0
                    y: e === "bottom" ? stage.height - stage.band : (e === "top" ? 0 : stage.band)
                    width: horizontal ? stage.width : stage.side
                    height: horizontal ? stage.band : stage.height - 2 * stage.band
                    radius: Theme.rSm
                    color: on ? Theme.accent : Theme.container
                    border.width: selected ? 2 : 1
                    border.color: selected ? Theme.fg : Theme.outline
                    opacity: Store.live ? 1 : 0.5
                    activeFocusOnTab: Store.live

                    Accessible.role: Accessible.CheckBox
                    Accessible.checkable: true
                    Accessible.checked: strip.on
                    Accessible.name: I18n.tr("settings.layout.edge_name." + e)

                    Keys.onSpacePressed: event => { screen.toggleBar(strip.e); event.accepted = true }
                    Keys.onReturnPressed: event => { screen.toggleBar(strip.e); event.accepted = true }
                    Keys.onEnterPressed: event => { screen.toggleBar(strip.e); event.accepted = true }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: strip.on ? Theme.fgOnAccent : Theme.fg
                            font.pixelSize: Theme.fs - 2
                            font.weight: strip.selected ? Theme.wBold : Theme.wMedium
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.tr("settings.layout.edge_short." + strip.e)
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: strip.on ? Theme.fgOnAccent : Theme.dim
                            font.pixelSize: Theme.fs - 3
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.tr(strip.on ? "settings.layout.bar_on" : "settings.layout.bar_off")
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: Store.live
                        onClicked: screen.toggleBar(strip.e)
                    }
                    FocusRing {
                        anchors.fill: parent
                        shown: strip.activeFocus
                        corner: strip.radius
                    }
                }
            }
        }

        // --- the radio group: which edge's section shows below. Arrows move it (Segmented), Space picks it. -------------
        Segmented {
            id: picker
            objectName: "edge-radio"
            width: Math.min(screen.width, 480)
            choices: screen.edges.map(function (e) { return { value: e, label: "settings.layout.edge_name." + e } })
            current: screen.edge
            enabled: Store.live
            cancellable: false
            onPicked: v => screen.pick(v)
            onPreviewed: v => screen.pick(v)
        }

        // --- the selected edge's bar, moved to a free edge (where a bar stands) -----------------------------------------
        Select {
            id: mover
            objectName: "move-bar"
            visible: screen.barOn(screen.edge)
            width: Math.min(screen.width, 280)
            label: I18n.tr("settings.layout.move_bar")
            placeholder: I18n.tr("settings.layout.move_bar")
            choices: screen.moveChoices()
            current: undefined
            enabled: Store.live && choices.length > 0
            onPicked: v => screen.moveBar(v)
        }
        Text {
            visible: screen.moveError !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.error
            font.pixelSize: Theme.fs - 2
            font.family: Theme.fam(text, Theme.families)
            text: "✕ " + I18n.tr("settings.ui.rejected") + ": " + screen.moveError
        }

        // --- what no edge shows (`unplaced`, K72): named, with its reason, and a zone to add it to ----------------------
        Repeater {
            model: { Store.docs; return Store.unplacedOf(screen.output) }
            delegate: Column {
                id: unplacedRow
                required property var modelData
                width: parent.width
                spacing: 2
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.fmt("settings.layout.unplaced", { name: Store.moduleName(unplacedRow.modelData.id) })
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.dim
                    font.pixelSize: Theme.fs - 2
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr(unplacedRow.modelData.reason)
                }
                Select {
                    objectName: "unplaced:" + unplacedRow.modelData.id
                    width: Math.min(parent.width, 360)
                    label: I18n.fmt("settings.layout.unplaced", { name: Store.moduleName(unplacedRow.modelData.id) })
                    placeholder: I18n.tr("settings.layout.add_to")
                    choices: screen.zoneChoices()
                    current: undefined
                    enabled: Store.live
                    onPicked: v => screen.addTo(unplacedRow.modelData.id, v)
                }
            }
        }
    }
}
