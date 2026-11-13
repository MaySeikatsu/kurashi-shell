import QtQuick
import Quickshell
import qs.core
import qs.components

// The terminal as a panel (`panel:terminal` → `mod:terminal:terminal`; docs/ux/terminal.md "The places"): the bar
// module's card in the Stage (hover or click), a sidebar section or tab, and the web dock's Local pin. The same session
// as the drop-down: this panel draws the tab row and a well and reports where the well rests (`terminal.place` with
// `card` or `sidebar`), and the terminal host lays its text over it. The place opened last shows the terminal; the
// others say where it is and bring it here on a press. While the card or the sidebar moves the report is withdrawn
// (the host's window unmaps; the sessions keep running).
Item {
    id: panel
    required property var store
    required property var theme
    required property var i18n

    // Set by a host that offers them (MODS.md "Panels"): the height on offer and where the panel rests in a sidebar; the
    // Stage's card hands `cardPlacement` ({output, rest, x, y, width, height} on the output).
    property real fillHeight: 0
    property var placement: null
    property var cardPlacement: null
    readonly property bool inCard: cardPlacement !== null && !placement
    readonly property string where: inCard ? "card" : (placement ? "sidebar" : "")

    width: parent ? parent.width : 560
    implicitHeight: fillHeight > 0 ? fillHeight : (inCard ? 380 : 420)
    // In the card: wide enough for 80 columns of the look's monospace at the terminal's size.
    implicitWidth: inCard ? 760 : 420

    Watch { doc: "mod.terminal" }
    readonly property var d: Store.docs["mod.terminal"] || ({})
    readonly property bool hasDoc: Store.docs["mod.terminal"] !== undefined

    TabRow {
        id: row
        width: parent.width
        doc: panel.d
        output: panel.cardPlacement ? String(panel.cardPlacement.output || "") : (panel.placement ? String(panel.placement.output || "") : "")
    }
    Rectangle {
        id: well
        y: row.height + Theme.xs
        width: parent.width
        height: Math.max(80, parent.height - y)
        radius: Theme.rSm
        color: Qt.alpha(Theme.surface, Math.max(0, Math.min(100, Number(panel.d.settings && panel.d.settings.opacity !== undefined ? panel.d.settings.opacity : 60))) / 100)
        Notice {
            anchors.fill: parent
            doc: panel.d
            place: panel.where !== "" ? panel.where : "none"
        }
        // Outside a card and a sidebar (a place that hands no placement): the terminal cannot be laid here; say so and
        // offer the drop-down.
        Column {
            visible: panel.where === "" && panel.hasDoc
            anchors.centerIn: parent
            spacing: Theme.gap
            Text {
                text: I18n.tr("terminal.state.unplaced")
                color: Theme.dim
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                label: I18n.tr("terminal.press.dropdown")
                onClicked: Store.act("terminal.show", {})
            }
        }
    }

    // ---- where the well rests on the output ----
    readonly property var qsw: panel.Window.window ? panel.QsWindow.window : null
    readonly property var wellPlace: {
        if (well.width < 1 || well.height < 1) return null
        if (inCard) {
            var cp = cardPlacement
            if (!cp || cp.rest !== true) return null
            return { where: "card", on: true, output: String(cp.output), x: Math.round(cp.x + well.x),
                     y: Math.round(cp.y + well.y), width: Math.round(well.width), height: Math.round(well.height) }
        }
        if (!placement || !qsw) return null
        var o = Light.originOf(qsw)
        var p = well.mapToItem(null, 0, 0)
        return { where: "sidebar", on: true, output: String(placement.output), x: Math.round(o.x + p.x),
                 y: Math.round(o.y + p.y), width: Math.round(well.width), height: Math.round(well.height) }
    }
    property string sent: ""
    property string sentWhere: ""
    function report() {
        var args = wellPlace
        if (!args) {
            if (sent === "" || sent === "off") return
            Store.act("terminal.place", { where: sentWhere, on: false })
            sent = "off"
            return
        }
        var key = JSON.stringify(args)
        if (key === sent) return
        // The first rest since this place opened makes it the one that shows the terminal ("last opened wins").
        if (sent === "") args = Object.assign({ fresh: true }, args)
        sent = key
        sentWhere = args.where
        Store.act("terminal.place", args)
    }
    onWellPlaceChanged: report()
    function close() {
        if (sent === "") return
        Store.act("terminal.place", { where: sentWhere, closed: true })
        sent = ""
    }
    Component.onDestruction: { close(); Peeks.hoverOverlay("terminal", false) }
    // The card closed (the Stage may keep the panel made a while after): the place is gone, the next rest is fresh.
    Watch { doc: "runtime.ui"; active: panel.inCard || panel.sentWhere === "sidebar" }
    readonly property bool cardShown: inCard && (Store.docs["runtime.ui"] || ({})).panel === "mod:terminal:terminal"
    onCardShownChanged: if (!cardShown) close()
    // The sidebar closed (it keeps its panels made): the place is gone too; a slide or a scroll is only a move.
    property string side: ""
    onPlacementChanged: if (placement && placement.side) side = String(placement.side)
    readonly property bool sideShown: side !== "" && (Store.docs["runtime.ui"] || ({})).sidebar === side
    onSideShownChanged: if (!sideShown && sentWhere === "sidebar") close()
    // The pointer in the host's window over the well holds a hover-opened card, as the card itself does.
    readonly property bool pageHover: inCard && cardShown && d.pointer === true
    onPageHoverChanged: Peeks.hoverOverlay("terminal", pageHover)
}
