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
    // B48 (docs/ux/bar-fit.md): the bar's fit — what the host's row gives it. `room`: an elastic module's most width
    // (the window list, the island's media title, a mod's line); `compact`: draw the short form (the icon); `parked`: in
    // the bar's overflow, not drawn here and not live (its widths are kept from when it was).
    property real room: 1e6
    property bool compact: false
    property bool parked: false
    property bool keys: false
    signal trayMenuRequested(string id)

    readonly property string mid: entry && entry.id ? String(entry.id) : ""
    readonly property bool isMod: !!entry && entry.kind === "mod"
    readonly property var item: loader.item
    readonly property bool present: !!item && item.present === true
    readonly property var slotHeights: item && item.present ? item.slotHeights : []
    readonly property bool busy: !!item && item.busy === true
    function geo() { return item ? item.geo() : [] }

    // (what the host's row counts: present, given a slot, not in the overflow)
    readonly property bool shown: present && fitSlots > 0 && !parked
    visible: shown
    // What the module says for the fit: its width full and compact, whatever it draws now, and for an elastic one the
    // least it elides to. While parked it is not live (a mod widget is not even loaded), so what it says then lapses: the
    // fit keeps what it said while it was drawn (ZoneRow `spec`), and a change while parked asks for no new fit.
    readonly property bool liveElastic: !!item && item.elastic === true
    readonly property real liveFull: item ? Math.ceil(item.fullW) : 0
    readonly property real liveCompact: item ? Math.ceil(Math.min(item.fullW, item.compactW)) : 0
    readonly property real liveMin: item ? Math.ceil(Math.min(item.fullW, item.minW)) : 0
    readonly property string fitKey: parked ? "parked"
        : [present, fitSlots > 0, liveElastic, liveFull, liveCompact, liveMin].join("|")
    width: item ? item.width : 0
    height: item ? item.height : 0

    // ---- the tab stop (keys) ----
    readonly property string a11yName: !item ? "" : (item.a11yName !== "" ? item.a11yName
        : (isMod ? mid : I18n.tr("layout.module." + mid)))
    activeFocusOnTab: keys && shown && !(item && item.ownsFocus)
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

    // ---- Open on hover (I458, K113, docs/ux/bar-hover.md) ----
    // What holds for this module (`bar.hover`, or its own entry in `bar.hover_*`).
    readonly property string hoverMode: mid !== "" ? Peeks.hoverModeOf(mid) : "preview"
    // The module's card, where a hover can open it without toggling it shut: a mod's panel, the clock's face, the quick
    // settings card, the launcher. "" for a module that has none: its hover stays its preview.
    // W70: a control's module (ControlModule) — its page in the control centre ("page"; one without a page has no card).
    readonly property string hoverSurface: isMod ? (item && item.hasPanel ? "mod" : "")
        : (["clock", "launcher"].indexOf(mid) >= 0 || (mid === "quick" && item && item.opensCard === true) ? mid
        : (item && item.cardPage !== undefined && item.cardPage !== "" ? "page" : ""))
    HoverHandler {
        id: hov
        enabled: host.shown && host.mid !== "" && host.hoverMode !== "preview"
        onHoveredChanged: {
            if (hovered) { if (Peeks.hoverOwner === host.mid) Peeks.hoverHold(); else hoverIntent.restart() }
            else { hoverIntent.stop(); Peeks.hoverLeft(host.mid) }
        }
    }
    Timer { id: hoverIntent; interval: Peeks.hoverIntentMs; onTriggered: host.hoverOpen() }
    function hoverOpen() {
        if (!hov.hovered || Peeks.hoverOwner === host.mid) return
        // (what a click opened stays as it is: only a hover's own card gives way to the next module's)
        if (Peeks.cardOpen && Peeks.hoverOwner === "") return
        if (hoverMode === "menu") openMenu()
        else if (hoverSurface === "mod" || hoverSurface === "clock" || hoverSurface === "launcher") {
            if (hoverSurface === "launcher" && Peeks.ui.launcher === true) return
            activate()
        } else if (hoverSurface === "quick") {
            if ((Peeks.ui.panel || "") === "quick") return
            Isl.IslandGeom.notePress(output, mid)
            Store.act("quick.toggle")
        } else if (hoverSurface === "page") {
            if (item.cardShown) return
            item.showCard()
        } else return
        Peeks.dismiss()
        Peeks.hoverOpened(host.mid)
    }
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
        enabled: !host.vertical && host.present && !host.parked
    }
    // (on a side edge its menu stands beside it, I408: a key of its own, a card still comes out as it did there)
    Isl.AnchorReport {
        target: host
        key: host.mid !== "" ? "side:" + host.mid : ""
        output: host.output
        enabled: host.vertical && host.present && !host.parked
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
        launcher: launcher,
        // W70: the control centre's controls, each a module of its own.
        wifi: wifiM, bluetooth: bluetoothM, audio: audioM, mic: micM, power: powerM, brightness: brightnessM, focus: focusM,
        caffeine: caffeineM, nightlight: nightlightM, darkmode: darkmodeM, airplane: airplaneM
    })
    Loader {
        id: loader
        sourceComponent: host.isMod ? modWidget : (host.core[host.mid] || null)
    }

    Component { id: workspaces; Workspaces { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: windows; Windows { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: island; Island { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: volume; Volume { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: recorder; Recorder { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: keyboard; Keyboard { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: clock; Clock { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: quick; Quick { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: tray; Tray { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room; onMenuRequested: id => host.trayMenuRequested(id) } }
    Component { id: sidebarLeft; SidebarToggle { side: "left"; vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: sidebarRight; SidebarToggle { side: "right"; vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: launcher; Launcher { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: wifiM; Wifi { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: bluetoothM; Bluetooth { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: audioM; AudioOut { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: micM; Mic { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: powerM; Power { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: brightnessM; Brightness { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: focusM; Focus { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: caffeineM; Caffeine { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: nightlightM; NightLight { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: darkmodeM; DarkMode { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: airplaneM; Airplane { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
    Component { id: modWidget; ModWidget { mod: host.entry.mod || ""; provide: host.entry.provide || ""; vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; hostFocused: host.activeFocus; compact: host.compact; room: host.room } }
}
