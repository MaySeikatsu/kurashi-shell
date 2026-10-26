import QtQuick
import "../../core"

// Loads one zone entry (`runtime.layout` zones, K72: `{id, kind: core|mod, mod?, provide?}`) as its module: a core one by
// id (this directory), a mod's glance through ModLoader (ModWidget). An id it does not know draws nothing (the daemon
// lists such an entry in `problems`; Settings offers to remove it). The host — a bar's zone, an edge module group — sets
// where it stands and reads back what the module says (`present`, `slotHeights`, `busy`); it is sized by its module and
// shown only while the module is present and, in a fitted column, given a slot.
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

    readonly property var core: ({
        workspaces: workspaces, windows: windows, island: island, volume: volume, recorder: recorder,
        keyboard: keyboard, clock: clock, quick: quick, tray: tray, sidebar_left: sidebarLeft, sidebar_right: sidebarRight
    })
    Loader {
        id: loader
        sourceComponent: host.isMod ? modWidget : (host.core[host.mid] || null)
    }

    Component { id: workspaces; Workspaces { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots } }
    Component { id: windows; Windows { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; room: host.room } }
    Component { id: island; Island { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots } }
    Component { id: volume; Volume { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots } }
    Component { id: recorder; Recorder { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots } }
    Component { id: keyboard; Keyboard { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots } }
    Component { id: clock; Clock { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots } }
    Component { id: quick; Quick { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots } }
    Component { id: tray; Tray { vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots; onMenuRequested: id => host.trayMenuRequested(id) } }
    Component { id: sidebarLeft; SidebarToggle { side: "left"; vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots } }
    Component { id: sidebarRight; SidebarToggle { side: "right"; vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots } }
    Component { id: modWidget; ModWidget { mod: host.entry.mod || ""; provide: host.entry.provide || ""; vertical: host.vertical; thickness: host.thickness; edge: host.edge; output: host.output; screen: host.screen; live: host.live; anchored: host.anchored; link: host.link; fitSlots: host.fitSlots } }
}
