import QtQuick
import Quickshell
import "../../core"

// The common face of a module's glance (K72: one id, every variant; this is the `glance` one): what a host — a bar's zone
// or an edge module group (W45) — tells it, and what it tells the host. Nothing here, and nothing in a module, may assume
// it stands in a Bar: the host hands in where it stands (`edge`, `vertical`, `thickness`, `output`, `screen`), whether it
// is shown (`live`: watches and loaders follow it, Ma) and a `link` for what modules of one host share (the workspace
// chips a window is dragged onto, ModuleLink).
Item {
    id: mb
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
    // The host's tab stop has the keyboard (a module whose peek follows focus asks for it then).
    property bool hostFocused: false

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
    // Its accessible name, from what the glance shows (W45: the host's tab stop says it); "" = the module's name.
    property string a11yName: ""
    // The module takes keyboard focus itself (a mod widget with its own tab stop): the host then adds none.
    property bool ownsFocus: false
    // Enter on the host's tab stop: the module's expanded view (the card its glance opens), else its primary action. A
    // module that has neither leaves it empty.
    function activate() {}
    // Test only (KURASHI_BAR_GEOMETRY): [[name, item], …] the host logs.
    function geo() { return [] }

    // Where its peeks hang from (row 514, PeekSource asks it): the host's edge and the window's place on the output.
    readonly property var qsWin: Window.window ? QsWindow.window : null
    function peekPlace() {
        var o = qsWin ? Light.originOf(qsWin) : Qt.point(0, 0)
        return { edge: mb.edge, ox: o.x, oy: o.y }
    }
}
