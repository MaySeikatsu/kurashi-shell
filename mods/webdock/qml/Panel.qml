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
// W72 (docs/ux/webdock.md "In the bar's card"): in the bar module's Stage card the Stage hands `cardPlacement` (where the
// panel rests on the output) and the page shows in the well the same way: this panel reports `webdock.card`, the host maps
// a window of its own over the well. The card has a pin of its own (`card.pin`); the pointer and the keyboard in the
// host's window hold the card open through the shell's overlay hook (Peeks.hoverOverlay), and the page's Esc closes it.
Item {
    id: panel
    required property var store
    required property var theme
    required property var i18n

    // Set by a host that offers them (MODS.md "Panels"): the height on offer, and where the panel rests in a sidebar.
    property real fillHeight: 0
    property var placement: null
    // W72: set by the Stage (its generic hook): `{output, rest, x, y, width, height}` on the output, `rest: false` while the
    // card moves. Null outside a Stage card.
    property var cardPlacement: null
    readonly property bool inCard: cardPlacement !== null && !placement
    // W73 (`mods.webdock.card_size`, docs/ux/webdock.md "The card's size"): the page's viewport in the card, from real
    // devices' CSS viewports less a browser's bars — phone 412 × 760, tablet 768 × 900, wide 1024 × 720; the well adds its
    // 36 px navigation row. The card takes that width round the well (contract row 66: the card's outer width; its padding
    // is the Stage's `pad + 4` on each side; the Stage clamps it to 360–1100 px and the output), so it shrinks, never runs
    // off screen.
    readonly property string cardSize: d.card_size === "tablet" || d.card_size === "wide" ? d.card_size : "phone"
    readonly property int viewW: cardSize === "wide" ? 1024 : cardSize === "tablet" ? 768 : 412
    readonly property int viewH: cardSize === "wide" ? 720 : cardSize === "tablet" ? 900 : 760
    readonly property int cardWidth: viewW + 2 * (Theme.pad + 4)

    width: parent ? parent.width : 420
    // In the card the well is the viewport and its navigation row tall, at most the output less the bars and the card's
    // margins (W72's clamp), at least 240 px.
    implicitHeight: fillHeight > 0 ? fillHeight : (inCard
        ? Math.max(240 + tile + Theme.gap, Math.min(viewH + 36 + tile + Theme.gap,
            (Screen.height > 0 ? Screen.height : 1080) - 2 * Theme.barH - 10 * Theme.pad))
        : 560)

    Watch { doc: "mod.webdock" }
    readonly property var d: Store.docs["mod.webdock"] || ({})
    readonly property bool hasDoc: Store.docs["mod.webdock"] !== undefined
    readonly property var pins: d.pins || []
    readonly property var sideDoc: d.sidebar || ({})
    readonly property var cardDoc: d.card || ({})
    readonly property string hostState: (d.host && d.host.state) || "off"
    readonly property string hostReason: (d.host && d.host.reason) || ""
    // The pin shown here: the daemon's sidebar pin (the card's own in a card), else the first (the daemon picks the same
    // once the panel rests).
    readonly property var ownDoc: inCard ? cardDoc : sideDoc
    readonly property string selId: ownDoc.pin !== undefined ? String(ownDoc.pin) : (pins.length > 0 ? String(pins[0].id) : "")
    readonly property var sel: pinOf(selId)
    readonly property bool selWeb: sel !== null && sel.kind === "web"
    readonly property var view: sel !== null && sel.kind === "view" ? viewOf(String(sel.target)) : null
    // W73: one page per pin, in the place opened last (docs/ux/webdock.md "Which place shows the page"): this place's pin
    // shown in another place says where (`elsewhere` of this place in the document: edge, sidebar, card). A daemon that
    // does not say (the mock) leaves W72's order: in a card, the sidebar's pin stays in the sidebar.
    readonly property string elsewhere: !selWeb ? ""
        : ownDoc.elsewhere !== undefined ? String(ownDoc.elsewhere)
        // (the sidebar's own `elsewhere` absent too: a daemon that publishes it says "card" when the card holds the page)
        : (inCard && sideDoc.place !== undefined && sideDoc.elsewhere === undefined && String(sideDoc.pin) === selId
            ? "sidebar" : "")
    readonly property bool shownElsewhere: elsewhere !== ""
    readonly property bool selLoaded: selWeb && sel.loaded === true
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
    // (a card's: on the output; a left sidebar's: x on the output, y from the usable area's top)
    function logHere() {
        if (!debugLog || !shownElsewhere || !notice.actionItem) return
        var c = notice.actionItem.mapToItem(panel, notice.actionItem.width / 2, notice.actionItem.height / 2)
        var cp = cardPlacement
        if (inCard && cp && cp.rest === true)
            console.log("webdock-panel here " + Math.round(cp.x + c.x) + " " + Math.round(cp.y + c.y))
        else if (placement && placement.side === "left")
            console.log("webdock-panel here-side " + Math.round(placement.inset + c.x) + " " + Math.round(placement.top + c.y))
    }
    onCardPlacementChanged: if (debugLog && shownElsewhere) hereLog.restart()
    onPlacementChanged: if (debugLog && shownElsewhere) hereLog.restart()
    // (test only: once the notice's column has laid out)
    Timer { id: hereLog; interval: 300; onTriggered: panel.logHere() }
    function choose(id) {
        if (placement) Store.act("webdock.sidebar_select", { pin: id })
        else if (inCard) Store.act("webdock.card_select", { pin: id })
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
        // W73: the panel's first rest is the sidebar opening on the dock (`fresh`: "last opened wins"); a rest after a
        // slide or a scroll is not.
        if (sent === "") args = Object.assign({ fresh: true }, args)
        sent = key
        if (debugLog) console.log("webdock-panel " + (wellPlace ? "place " + args.output + " " + args.side + " " + args.inset
            + " " + args.top + " " + args.width + " " + args.height + " panel " + Math.round(panel.width) + " "
            + Math.round(panel.height) + " at " + Math.round(placement.inset) + " " + Math.round(placement.top)
            + " pitch " + (panel.tile + Theme.gap) : "off"))
        Store.act("webdock.sidebar", args)
    }
    onWellPlaceChanged: report()
    Component.onDestruction: {
        if (sent !== "" && sent !== JSON.stringify({ on: false })) Store.act("webdock.sidebar", { on: false })
        if (cardPlaced) Store.act("webdock.card", { on: false })
        Peeks.hoverOverlay("webdock", false)
    }

    // ---- W72: the well's place on the output while the bar card rests, reported on change only ----
    readonly property var cardWellPlace: {
        var cp = cardPlacement
        if (!inCard || !cp || cp.rest !== true || well.width < 1 || well.height < 1) return null
        return { on: true, output: String(cp.output), x: Math.round(cp.x + well.x), y: Math.round(cp.y + well.y),
                 width: Math.round(well.width), height: Math.round(well.height) }
    }
    property string cardSent: ""
    readonly property bool cardPlaced: cardSent !== "" && cardSent !== JSON.stringify({ on: false })
    function reportCard() {
        var args = cardWellPlace || { on: false }
        var key = JSON.stringify(args)
        if (key === cardSent) return
        if (cardSent === "" && !cardWellPlace) return
        // W73: the card's first rest since it opened (the panel is made with the card) is an opening: `fresh`.
        if (cardSent === "") args = Object.assign({ fresh: true }, args)
        cardSent = key
        if (debugLog) console.log("webdock-panel card " + (cardWellPlace ? args.output + " " + args.x + " " + args.y + " "
            + args.width + " " + args.height + " panel " + Math.round(cardPlacement.x) + " " + Math.round(cardPlacement.y)
            + " " + Math.round(cardPlacement.width) + " " + Math.round(cardPlacement.height) + " pitch "
            + (panel.tile + Theme.gap) : "off"))
        Store.act("webdock.card", args)
    }
    onCardWellPlaceChanged: reportCard()
    // The pointer in the host's window over the well holds the card as the card itself does; a press there (or the
    // keyboard asked for the page) makes it the user's. Esc in the page's window, or "Show at the edge", asks the card to
    // close: the counter's value when the panel first sees the document is the baseline (an earlier close is not this
    // card's).
    readonly property bool pageHover: inCard && cardDoc.hover === true
    onPageHoverChanged: Peeks.hoverOverlay("webdock", pageHover)
    readonly property bool pageEngaged: inCard && cardDoc.engaged === true
    onPageEngagedChanged: if (pageEngaged) Peeks.hoverKeep()
    readonly property int closeAsks: cardDoc.close !== undefined ? cardDoc.close : 0
    property int closeSeen: -1
    onCloseAsksChanged: {
        if (!hasDoc) return
        if (closeSeen >= 0 && closeAsks > closeSeen && inCard) Store.act("ui.close")
        closeSeen = closeAsks
    }
    onHasDocChanged: if (hasDoc && closeSeen < 0) closeSeen = closeAsks
    Component.onCompleted: if (hasDoc) closeSeen = closeAsks

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
        // W72: Tab past the card's last key hands the keyboard to the page (the host's window asks for it once).
        Keys.onTabPressed: event => {
            if (panel.inCard && panel.selWeb && !panel.shownElsewhere && panel.cardPlaced) {
                Store.act("webdock.card_focus")
                event.accepted = true
            } else event.accepted = false
        }
    }

    // ---- the well: the page area. The host's page covers it while it shows; under it, what the shell knows ----
    Rectangle {
        id: well
        Component.onCompleted: Light.addPicture(well, Window.window)
        Component.onDestruction: Light.removePicture(well)
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
            id: notice
            anchors.fill: parent
            visible: text !== ""
            // (test only: what the well says, mods/webdock/test/test-card.sh)
            onTextChanged: if (panel.debugLog) console.log("webdock-panel notice " + (text === "" ? "-" : text))
            // (test only: where "Show here" is on the output while the card rests, test-card.sh)
            onActionLabelChanged: if (panel.debugLog) hereLog.restart()
            text: !panel.hasDoc ? I18n.tr("webdock.dock.unavailable")
                : panel.pins.length === 0 ? I18n.tr("webdock.empty")
                : panel.sel !== null && panel.sel.kind === "view" ? (viewBody.item === null ? I18n.tr("webdock.view.gone") : "")
                : !panel.selWeb ? ""
                : panel.hostState === "missing" ? I18n.tr("webdock.host.missing")
                : panel.hostState === "failed" ? I18n.tr(panel.hostReason || "webdock.dock.host.failed")
                // W73: the pin's page is in a place opened later: the well says where, with "Show here". Otherwise the
                // page comes once the card rests (W72), and a page already loaded needs no word meanwhile.
                : panel.shownElsewhere ? I18n.tr(panel.elsewhere === "edge" ? "webdock.edge.elsewhere"
                    : panel.elsewhere === "card" ? "webdock.card.elsewhere" : "webdock.side.elsewhere")
                : panel.inCard ? (panel.hostState !== "ready" ? I18n.tr("webdock.host.starting")
                    : (panel.selLoaded ? "" : I18n.tr("webdock.loading")))
                : !panel.placement ? I18n.tr("webdock.side.unplaced")
                : panel.hostState === "ready" ? I18n.tr("webdock.loading")
                : I18n.tr("webdock.host.starting")
            actionLabel: panel.pins.length === 0 ? I18n.tr("webdock.dock.empty.add")
                : panel.shownElsewhere && panel.hasDoc && panel.hostState !== "missing" && panel.hostState !== "failed"
                    ? I18n.tr("webdock.elsewhere.here")
                : (panel.selWeb && !panel.placement && !panel.inCard && panel.hasDoc ? I18n.tr("webdock.side.at_edge") : "")
            onActionPressed: {
                if (panel.pins.length === 0) Store.act("settings.open", { key: "mods.webdock.pins" })
                // W73: "Show here" picks the pin in this place again, which makes it the place opened last.
                else if (panel.shownElsewhere) panel.choose(panel.selId)
                else Store.act("webdock.open", { pin: panel.selId })
            }
        }
    }
}
