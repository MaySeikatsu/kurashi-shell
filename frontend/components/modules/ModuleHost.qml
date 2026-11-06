import QtQuick
import "../../core"
import ".." as C
import "../island" as Isl

// Loads one zone entry (`runtime.layout` zones, K72: `{id, kind: core|mod, mod?, provide?}`) as its module: a core one by
// id (this directory), a mod's glance through ModLoader (ModWidget). An id it does not know draws nothing (the daemon
// lists such an entry in `problems`; Settings offers to remove it). The host — a bar's zone, an edge module group — sets
// where it stands and reads back what the module says (`present`, `slotHeights`, `busy`); it is sized by its module and
// shown only while the module is present and, in a fitted column, given a slot.
// W45 (`keys`): a host that walks its modules by keyboard (an edge module group) makes each present module one tab stop
// with a focus ring and the module's accessible name; Enter (Return, Space) runs the module's `activate()` — its expanded
// view. A module that takes the keyboard itself (a mod widget with its own tab stop) gets no second stop.
Item {
    id: host
    property var entry: ({})
    property bool vertical: false
    property int thickness: Theme.barH
    property string edge: "top"
    property string output: ""
    property var screen: null
    property bool live: true
    property bool anchored: true
    property var link: null
    property int fitSlots: 1000000
    // The window list's room along the host (px); see Windows.qml.
    property real room: 1e6
    property bool keys: false
    signal trayMenuRequested(string id)

    readonly property string mid: entry && entry.id ? String(entry.id) : ""
    readonly property bool isMod: !!entry && entry.kind === "mod"
    readonly property var item: loader.item
    readonly property bool present: !!item && item.present === true
    readonly property var slotHeights: item && item.present ? item.slotHeights : []
    readonly property bool busy: !!item && item.busy === true
    function geo() { return item ? item.geo() : [] }

    visible: present && fitSlots > 0
    width: item ? item.width : 0
    height: item ? item.height : 0

    // ---- the tab stop (keys) ----
    readonly property string a11yName: !item ? "" : (item.a11yName !== "" ? item.a11yName
        : (isMod ? mid : I18n.tr("layout.module." + mid)))
    activeFocusOnTab: keys && present && fitSlots > 0 && !(item && item.ownsFocus)
    Accessible.role: keys ? Accessible.Button : Accessible.NoRole
    Accessible.name: keys ? a11yName : ""
    Accessible.focusable: activeFocusOnTab
    function activate() { if (item) { Isl.IslandGeom.notePress(output, mid); item.activate() } }
    Keys.onReturnPressed: activate()
    Keys.onEnterPressed: activate()
    Keys.onSpacePressed: activate()
    // I408 (docs/ux/module-menu.md): a right click, or the Menu key on its tab stop, opens the module's own menu in the
    // Stage, unless the module answers it itself (a tray icon's menu, a window's menu, a mod's own): a child that takes the
    // button keeps the event from reaching this handler.
    function openMenu() {
        Isl.IslandGeom.notePress(output, mid)
        Store.act("tray.menu.open", { id: "module:" + mid })
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        enabled: host.present && host.mid !== ""
        onTapped: host.openMenu()
    }
    Keys.onMenuPressed: openMenu()
    C.FocusRing {
        anchors.fill: parent
        anchors.margins: 1
        corner: Theme.rSm
        shown: host.activeFocus
    }

    // I340: every module on a top or bottom bar is an origin a card can come out of (`module:<id>`), and says when it is
    // pressed (a passive point handler: the module's own handlers keep the press), so the card a press opens comes out
    // under it, or at the bar's centre (`bar.popups`, `bar.popups_other`; Stage.qml).
    Isl.AnchorReport {
        target: host
        key: host.mid !== "" ? "module:" + host.mid : ""
        output: host.output
        enabled: !host.vertical && host.present
    }
    // (on a side edge its menu stands beside it, I408: a key of its own, a card still comes out as it did there)
    Isl.AnchorReport {
        target: host
        key: host.mid !== "" ? "side:" + host.mid : ""
        output: host.output
        enabled: host.vertical && host.present
    }
    PointHandler {
        acceptedButtons: Qt.AllButtons
        // (W59.9a: and where in the module, so an iris opens from the press)
        onActiveChanged: if (active) Isl.IslandGeom.notePress(host.output, host.mid,
            point.position.x / Math.max(1, host.width), point.position.y / Math.max(1, host.height))
    }

    readonly property var core: ({
        workspaces: workspaces, windows: windows, island: island, volume: volume, recorder: recorder,
        keyboard: keyboard, clock: clock, quick: quick, tray: tray, sidebar_left: sidebarLeft, sidebar_right: sidebarRight,
        launcher: launcher
    })
    Loader {
        id: loader
        sourceComponent: host.isMod ? modWidget : (host.core[host.mid] || null)
    }

    Component { id: workspaces; Workspaces { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus } }
    Component { id: windows; Windows { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; room: host.room } }
    Component { id: island; Island { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus } }
    Component { id: volume; Volume { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus } }
    Component { id: recorder; Recorder { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus } }
    Component { id: keyboard; Keyboard { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus } }
    Component { id: clock; Clock { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus } }
    Component { id: quick; Quick { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus } }
    Component { id: tray; Tray { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; onMenuRequested: id => host.trayMenuRequested(id) } }
    Component { id: sidebarLeft; SidebarToggle { side: "left"; vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus } }
    Component { id: sidebarRight; SidebarToggle { side: "right"; vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus } }
    Component { id: launcher; Launcher { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus } }
    Component { id: modWidget; ModWidget { mod: host.entry.mod || ""; provide: host.entry.provide || ""; vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus } }
}
