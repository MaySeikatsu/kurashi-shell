import QtQuick
import Quickshell
import "../../core"
import "../../core/mods.js" as Mods
import ".."
import "../island"

// The left sidebar's column (docs/ux/sidebar.md; ii `sidebarLeft/SidebarLeftContent.qml`: a tab bar over the panes):
// one tab per `sidebar.left` entry `mod:<id>:<panel>` whose mod is on and has that panel, the tab bar on top, the panel
// under it (ModLoader: made while its tab is shown, so a hidden tab holds no subscription; it scrolls when taller). A tab
// whose mod is not loaded or off is skipped; with none left, the column says which tabs are missing and why, with the
// way to the setting (Shōjiki). Ctrl+PageUp / Ctrl+PageDown switch tabs; the tabs are Tab stops with their names.
Item {
    id: lc
    property var tabs: []
    Watch { doc: "mods" }
    readonly property var modsDoc: Store.docs["mods"]

    function entryOf(id) {
        var list = (modsDoc && modsDoc.mods) || []
        for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
        return null
    }
    // Every configured tab with its state: ok, or why it is skipped (unknown, not_loaded, off, no_panel).
    readonly property var rows: {
        var out = []
        for (var i = 0; i < tabs.length; i++) {
            var ref = Mods.panelOf(tabs[i])
            var e = ref ? entryOf(ref.mod) : null
            var state = ref === null ? "unknown"
                : e === null || e.state === "detected" ? "not_loaded"
                : e.state !== "enabled" ? "off"
                : Mods.qmlOf(modsDoc, "panel:" + ref.panel, ref.mod) === "" ? "no_panel" : "ok"
            out.push({ value: tabs[i], ref: ref, state: state,
                       name: e && e.name ? I18n.tr(String(e.name)) : (ref ? ref.mod : String(tabs[i])) })
        }
        return out
    }
    readonly property var shownTabs: rows.filter(function (r) { return r.state === "ok" })
    property int current: 0
    readonly property int cur: Math.max(0, Math.min(current, shownTabs.length - 1))
    readonly property var tab: shownTabs.length > 0 ? shownTabs[cur] : null
    // Test only (KURASHI_SIDEBAR_GEOMETRY=1, frontend/test-sidebar-panel.sh): which tab shows, and its component.
    readonly property string shownLog: (tab ? tab.value : "none") + " " + (tab ? panel.resolved !== "" : false)
        + " " + rows.map(function (r) { return r.value + "=" + r.state }).join(",")
    onShownLogChanged: if (Quickshell.env("KURASHI_SIDEBAR_GEOMETRY") === "1") console.log("sidebar-tab " + shownLog)
    Component.onCompleted: if (Quickshell.env("KURASHI_SIDEBAR_GEOMETRY") === "1") console.log("sidebar-tab " + shownLog)
    function step(n) {
        if (shownTabs.length < 2) return
        current = (cur + n + shownTabs.length) % shownTabs.length
    }
    Keys.onPressed: event => {
        if (!(event.modifiers & Qt.ControlModifier)) return
        if (event.key === Qt.Key_PageDown) { step(1); event.accepted = true }
        else if (event.key === Qt.Key_PageUp) { step(-1); event.accepted = true }
    }

    // The tab bar: one key per tab, the current one tonal. Hidden with a single tab (nothing to switch).
    Row {
        id: bar
        visible: lc.shownTabs.length > 1
        width: lc.width
        height: visible ? implicitHeight : 0
        spacing: Theme.gap
        Repeater {
            model: lc.shownTabs
            delegate: KeyButton {
                required property var modelData
                required property int index
                side: 30
                label: modelData.name
                primary: index === lc.cur
                a11y: modelData.name
                onClicked: lc.current = index
            }
        }
    }
    // The tab's panel.
    Flickable {
        id: pane
        visible: lc.tab !== null
        y: bar.height + (bar.visible ? Theme.pad : 0)
        width: lc.width
        height: lc.height - y
        contentWidth: width
        contentHeight: Math.max(height, panel.height)
        boundsBehavior: Flickable.StopAtBounds
        interactive: panel.height > height + 1
        clip: true
        ModLoader {
            id: panel
            width: pane.width
            height: item ? Math.max(item.implicitHeight, pane.height) : 0
            provide: lc.tab ? "panel:" + lc.tab.ref.panel : ""
            mod: lc.tab ? lc.tab.ref.mod : ""
        }
        // The height on offer, for a panel that can fill it (optional `fillHeight`, MODS.md "Panels"; row 238).
        Binding {
            target: panel.item
            property: "fillHeight"
            value: pane.height
            when: panel.item !== null && panel.item.fillHeight !== undefined
        }
    }
    // Nothing to show: which tabs are missing, and why.
    Column {
        visible: lc.tab === null
        width: lc.width
        spacing: Theme.gap
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.fg
            font.pixelSize: Theme.fsTitle
            font.weight: Theme.wBold
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("sidebar.left.empty")
        }
        Repeater {
            model: lc.rows
            delegate: Text {
                required property var modelData
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("sidebar.left.missing." + modelData.state).replace("{name}", modelData.name)
            }
        }
        KeyButton {
            side: 30
            icon: "settings"
            label: I18n.tr("sidebar.left.settings")
            onClicked: Store.act("settings.open", {key: "sidebar.left"})
        }
    }
}
