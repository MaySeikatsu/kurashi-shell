import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../core"
import ".."
import "../modules" as M

// The bar's overflow card (B48, docs/ux/bar-fit.md): the modules a zone's fit had no room for, drawn as on the bar at full
// width, in a card under the "…" button (above it on a bottom bar). An overlay over the output while open, so a press
// outside closes it and the keyboard reaches it (a popup of a layer surface without keyboard gets none — the window
// list's menu, K51): Tab walks the modules (each a tab stop with its accessible name), Enter opens a module's expanded
// view, the Menu key its menu, Esc closes. Made on open, gone on close (Bar.qml's LazyLoader).
PanelWindow {
    id: ov
    required property var owner
    // The entries (`{id, kind, mod?, provide?}`), in the zone's order, and the button's box on the output.
    property var entries: []
    property rect at: Qt.rect(0, 0, 0, 0)
    signal dismissed()

    screen: owner.scr
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "kurashi-bar-overflow"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    // Glass: behind the card's block, without its shadow (I296).
    BackgroundEffect.blurRegion: Region {
        x: Theme.blur ? card.x : 0
        y: card.y
        width: Theme.blur ? card.width : 0
        height: Theme.blur ? card.height - Theme.shadowDy : 0
        radius: Theme.rLg
    }
    // A card a module opens (its expanded view, its menu) takes the screen: this one goes.
    readonly property var ui: Store.docs["runtime.ui"] || ({})
    readonly property bool cardOpen: !!ui.panel || !!ui.tray
    onCardOpenChanged: if (cardOpen) ov.dismissed()

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: function (ev) {
            var inside = ev.x >= card.x && ev.x < card.x + card.width && ev.y >= card.y && ev.y < card.y + card.height
            if (inside) ev.accepted = false
            else ov.dismissed()
        }
    }
    // The keyboard: the card's own tab stops (Tab walks them, the window's focus chain); Esc from wherever the focus is
    // (a key a module does not take climbs to here).
    FocusScope {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: ov.dismissed()
        Block {
            id: card
            readonly property bool below: ov.owner.edge !== "bottom"
            x: Math.max(Theme.gap, Math.min(ov.width - width - Theme.gap, ov.at.x + ov.at.width / 2 - width / 2))
            y: below ? ov.at.y + ov.at.height + Theme.gap : ov.at.y - Theme.gap - height
            width: row.width + 2 * Theme.pad + 2 * inset
            height: Theme.barH + 2 * Theme.xs + 2 * inset + Theme.shadowDy
            radius: Theme.rLg
            fill: Theme.panel
            flatBorder: Theme.outline
            softScale: 0.6
            Accessible.role: Accessible.Grouping
            Accessible.name: I18n.tr("frontend.bar.overflow.card")
            Row {
                id: row
                x: Theme.pad + card.inset
                y: Theme.xs + card.inset
                height: Theme.barH
                spacing: Theme.pad
                Repeater {
                    id: rep
                    model: ov.entries
                    delegate: M.ModuleHost {
                        required property var modelData
                        entry: modelData
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                        thickness: ov.owner.barH
                        vertical: false
                        edge: ov.owner.edge
                        output: ov.owner.outName
                        screen: ov.owner.scr
                        live: true
                        anchored: true
                        link: ov.owner.link
                        keys: true
                        // (a long title still elides here: at most a third of the output)
                        room: Math.round((ov.owner.scr ? ov.owner.scr.width : 1920) / 3)
                        onTrayMenuRequested: id => ov.owner.trayMenuRequested(id)
                        Keys.onEscapePressed: ov.dismissed()
                    }
                }
            }
        }
    }

    function firstStop() {
        for (var i = 0; i < rep.count; i++) {
            var h = rep.itemAt(i)
            if (h && h.visible) return h.activeFocusOnTab ? h : (h.nextItemInFocusChain(true) || h)
        }
        return null
    }
    Component.onCompleted: Qt.callLater(function () { var f = ov.firstStop(); if (f) f.forceActiveFocus() })
    // Test only (KURASHI_BAR_GEOMETRY=1, frontend/test-bar-fit.sh): the card's modules once laid out, and its going.
    readonly property bool logOn: Quickshell.env("KURASHI_BAR_GEOMETRY") === "1"
    Timer {
        running: ov.logOn
        interval: 400
        onTriggered: {
            var ids = []
            for (var i = 0; i < rep.count; i++) { var h = rep.itemAt(i); if (h && h.visible) ids.push(h.mid) }
            console.log("BAROVERFLOW open " + ov.owner.outName + " " + ov.owner.edge + " " + (ids.join(",") || "-"))
        }
    }
    // (and which module has the keyboard: the host round the focused item)
    Item {
        readonly property Item afi: Window.activeFocusItem
        onAfiChanged: {
            if (!ov.logOn) return
            var it = afi
            while (it && it.mid === undefined) it = it.parent
            console.log("BAROVERFLOW focus " + (it ? it.mid : (afi ? "card" : "-")))
        }
    }
    Component.onDestruction: if (logOn) console.log("BAROVERFLOW closed " + owner.outName + " " + owner.edge)
}
