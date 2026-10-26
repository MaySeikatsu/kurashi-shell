import QtQuick
import "../../core"

// The common face of a module's glance (K72: one id, every variant; this is the `glance` one): what a host — a bar's zone
// today, an edge module group later (W45) — tells it, and what it tells the host. Nothing here, and nothing in a module,
// may assume it stands in a Bar: the host hands in where it stands (`edge`, `vertical`, `thickness`, `output`, `screen`),
// whether it is shown (`live`: watches and loaders follow it, Ma) and a `link` for what modules of one host share (the
// workspace chips a window is dragged onto, ModuleLink).
Item {
    // Where it stands: a side edge draws the module for a column `thickness` wide, a top or bottom one for a row that tall.
    property bool vertical: false
    property int thickness: Theme.barH
    property string edge: "top"
    // The output's name and its ShellScreen (tray coordinates, the window list's output).
    property string output: ""
    property var screen: null
    // The host is shown: documents are watched and mod widgets loaded only then (Ma).
    property bool live: true
    // Register the origins a Stage panel grows out of (IslandGeom's registry): one host per output does.
    property bool anchored: true
    property var link: null

    // ---- what the module tells its host ----
    // It has something to show now (a recording, more than one layout, tray items). A host lays out only present modules
    // (no spacing for an absent one); computed from data, never from `visible` (a host gates its own visibility on it).
    property bool present: true
    // A side column's slots, top to bottom (heights, px): the host's fit counts them and hides the column's end first
    // (`+N`). Most modules are one slot; the tray is one per icon.
    property var slotHeights: [height]
    // How many of its slots the host's fit gives it (a side column's end); all of them elsewhere.
    property int fitSlots: 1000000
    // Something of it is open (a menu, a drag): a hover-revealed host stays out.
    property bool busy: false
    // Test only (KURASHI_BAR_GEOMETRY): [[name, item], …] the host logs.
    function geo() { return [] }
}
