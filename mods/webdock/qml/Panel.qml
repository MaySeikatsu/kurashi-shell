import QtQuick
import Quickshell
import qs.core
import qs.components

// The web dock as a sidebar tab or section (W30, `panel:webdock` → `mod:webdock:webdock`; docs/ux/webdock.md "In the
// sidebar"). Not phone shaped: the pins sit as a row of app keys on top (Zen's Essentials row; Vivaldi's and Edge's
// panels put the same icons in a column, which costs a 48 px stripe of a 320 px sidebar), and the shown pin fills the
// rest of the pane, edge to edge inside the sidebar's padding and the full height on offer (`fillHeight`).
// A site's page is the web host's (one host, one set of pages, K38): this panel reports where its page area rests in
// the sidebar's window (`webdock.sidebar`, from the sidebar's `placement`) and the host maps the page there, over the
// well this panel draws; a view pin's panel is drawn here, by the shell. While the sidebar slides, scrolls or closes
// the placement is withdrawn and the host's window unmaps (0 frames); the page stays loaded under the dock's own rules.
// Outside a sidebar (no `placement`: a Stage card) a click on a pin shows it at the edge instead.
Item {
    id: panel
    required property var store
    required property var theme
    required property var i18n

    // Set by a host that offers them (MODS.md "Panels"): the height on offer, and where the panel rests in a sidebar.
    property real fillHeight: 0
    property var placement: null

    width: parent ? parent.width : 420
    implicitHeight: fillHeight > 0 ? fillHeight : 560

    Watch { doc: "mod.webdock" }
    readonly property var d: Store.docs["mod.webdock"] || ({})
    readonly property bool hasDoc: Store.docs["mod.webdock"] !== undefined
    readonly property var pins: d.pins || []
    readonly property var sideDoc: d.sidebar || ({})
    readonly property string hostState: (d.host && d.host.state) || "off"
    readonly property string hostReason: (d.host && d.host.reason) || ""
    // The pin shown here: the daemon's sidebar pin, else the first (the daemon picks the same once the panel rests).
    readonly property string selId: sideDoc.pin !== undefined ? String(sideDoc.pin) : (pins.length > 0 ? String(pins[0].id) : "")
    readonly property var sel: pinOf(selId)
    readonly property bool selWeb: sel !== null && sel.kind === "web"
    readonly property var view: sel !== null && sel.kind === "view" ? viewOf(String(sel.target)) : null
    readonly property bool debugLog: Quickshell.env("KURASHI_WEBDOCK_DEBUG") === "1"
        || Quickshell.env("KURASHI_SIDEBAR_GEOMETRY") === "1"

    function pinOf(id) {
        for (var i = 0; i < pins.length; i++)
            if (String(pins[i].id) === id) return pins[i]
        return null
    }
    // `mod:<id>:<panel>` as { mod, panel } (frontend/core/mods.js panelOf); the dock's own panel is not a view of itself.
    function viewOf(target) {
        var s = String(target || "")
        if (s.indexOf("mod:") !== 0) return null
        var rest = s.substring(4)
        var c = rest.indexOf(":")
        if (c <= 0 || c === rest.length - 1) return null
        var v = { mod: rest.substring(0, c), panel: rest.substring(c + 1) }
        return v.mod === "webdock" ? null : v
    }
    function choose(id) {
        if (placement) Store.act("webdock.sidebar_select", { pin: id })
        else Store.act("webdock.open", { pin: id })
    }

    // ---- the page area's place in the sidebar window, reported on change only ----
    // The well's rect from the window's anchored side edge and top: the panel's placement plus the well's offset.
    readonly property var wellPlace: {
        if (!placement || well.width < 1 || well.height < 1) return null
        var right = placement.side === "right"
        return {
            on: true, output: String(placement.output), side: String(placement.side),
            inset: Math.round(placement.inset + (right ? panel.width - well.x - well.width : well.x)),
            top: Math.round(placement.top + well.y),
            width: Math.round(well.width), height: Math.round(well.height)
        }
    }
    property string sent: ""
    function report() {
        var args = wellPlace || { on: false }
        var key = JSON.stringify(args)
        if (key === sent) return
        // The first report of a panel is never an "off": nothing was placed yet.
        if (sent === "" && !wellPlace) return
        sent = key
        if (debugLog) console.log("webdock-panel " + (wellPlace ? "place " + args.output + " " + args.side + " " + args.inset
            + " " + args.top + " " + args.width + " " + args.height + " panel " + Math.round(panel.width) + " "
            + Math.round(panel.height) + " at " + Math.round(placement.inset) + " " + Math.round(placement.top)
            + " pitch " + (panel.tile + Theme.gap) : "off"))
        Store.act("webdock.sidebar", args)
    }
    onWellPlaceChanged: report()
    Component.onDestruction: if (sent !== "" && sent !== JSON.stringify({ on: false })) Store.act("webdock.sidebar", { on: false })

    Accessible.role: Accessible.Pane
    Accessible.name: I18n.tr("webdock.dock.name")

    // ---- the pins: one row of app keys, scrolling sideways when they do not fit ----
    readonly property int tile: 40
    Flickable {
        id: row
        width: panel.width - settingsKey.width - Theme.gap
        height: panel.tile + Theme.shadowDy
        contentWidth: pinRow.width
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width + 1
        clip: true
        visible: panel.pins.length > 0
        Row {
            id: pinRow
            spacing: Theme.gap
            Repeater {
                model: panel.pins
                delegate: PinTile {
                    required property var modelData
                    pin: modelData
                    tileSize: panel.tile
                    shown: String(modelData.id) === panel.selId
                    onActivated: panel.choose(String(modelData.id))
                    onMenuRequested: Store.act("settings.open", { key: "mods.webdock.pins" })
                    onTabbed: back => {
                        var n = nextItemInFocusChain(!back)
                        if (n) n.forceActiveFocus()
                    }
                }
            }
        }
    }
    IconButton {
        id: settingsKey
        anchors.right: parent.right
        y: Math.round((panel.tile - height) / 2)
        icon: "settings"
        glyph: "⚙"
        a11y: I18n.tr("webdock.dock.settings")
        onClicked: Store.act("settings.open", { key: "mods.webdock.pins" })
    }

    // ---- the well: the page area. The host's page covers it while it shows; under it, what the shell knows ----
    Rectangle {
        id: well
        y: panel.pins.length > 0 ? row.height + Theme.gap : settingsKey.height + Theme.gap
        width: panel.width
        height: Math.max(0, panel.height - y)
        radius: Theme.rLg
        color: Theme.containerHigh
        border.width: Theme.outlineW > 0 ? Theme.outlineW : 1
        border.color: Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline
        clip: true

        // A view pin: its mod's panel, drawn here and given the well's height.
        ModLoader {
            id: viewBody
            x: Theme.pad
            y: Theme.pad
            width: well.width - 2 * Theme.pad
            height: item ? Math.max(item.implicitHeight, well.height - 2 * Theme.pad) : 0
            provide: panel.view ? "panel:" + panel.view.panel : ""
            mod: panel.view ? panel.view.mod : ""
            shown: panel.view !== null
        }
        Binding {
            target: viewBody.item
            property: "fillHeight"
            value: well.height - 2 * Theme.pad
            when: viewBody.item !== null && viewBody.item.fillHeight !== undefined
        }
        Notice {
            anchors.fill: parent
            visible: text !== ""
            text: !panel.hasDoc ? I18n.tr("webdock.dock.unavailable")
                : panel.pins.length === 0 ? I18n.tr("webdock.empty")
                : panel.sel !== null && panel.sel.kind === "view" ? (viewBody.item === null ? I18n.tr("webdock.view.gone") : "")
                : !panel.selWeb ? ""
                : panel.hostState === "missing" ? I18n.tr("webdock.host.missing")
                : panel.hostState === "failed" ? I18n.tr(panel.hostReason || "webdock.dock.host.failed")
                : !panel.placement ? I18n.tr("webdock.side.unplaced")
                : panel.hostState === "ready" ? I18n.tr("webdock.loading")
                : I18n.tr("webdock.host.starting")
            actionLabel: panel.pins.length === 0 ? I18n.tr("webdock.dock.empty.add")
                : (panel.selWeb && !panel.placement && panel.hasDoc ? I18n.tr("webdock.side.at_edge") : "")
            onActionPressed: {
                if (panel.pins.length === 0) Store.act("settings.open", { key: "mods.webdock.pins" })
                else Store.act("webdock.open", { pin: panel.selId })
            }
        }
    }
}
