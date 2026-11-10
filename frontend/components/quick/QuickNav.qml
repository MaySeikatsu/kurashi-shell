pragma Singleton
import QtQuick
import Quickshell
import "../../core"

// Which page of the control centre a control's bar module opens (W70, docs/ux/control-centre-modules.md). The daemon
// keeps which card is open (`runtime.ui.panel = quick`), not yet which page: CONTRACT-CHANGE row 710 asks for
// `quick.toggle {page}` and `runtime.ui.quick_page`. Until the lead takes it this is the stand-in: a module says the page
// here and asks for the card; the card, once made, takes the page (QuickPanel), and says which page it shows. The
// argument is sent already (both daemons ignore it today), so the row changes only where the page is read.
Singleton {
    id: nav
    readonly property var ui: Store.docs["runtime.ui"] || ({})
    readonly property bool cardOpen: ui.panel === "quick"
    // The page asked for and not yet taken by a card ("" none).
    property string asked: ""
    // Bumped by every ask, so an open card follows an ask for the page it already had asked for.
    property int serial: 0
    // The page the open card shows ("" its tiles, or no card); QuickPanel keeps it.
    property string shown: ""
    // The module that asked for the page shown ("" when the card got there itself: its tiles, the status line). Two
    // modules share a page (airplane mode is on the Wi-Fi page): only the one that opened it draws itself pressed.
    property string by: ""

    // Opens the card on `page` for module `who`, or closes it when that module's page is already up.
    function open(page, who) {
        if (cardOpen && shown === page) {
            if (by === who) { Store.act("ui.close", {}); return }
            by = who
            return
        }
        asked = page
        by = who
        serial++
        if (cardOpen) return    // the open card turns to the page (QuickPanel follows `serial`)
        Store.act("quick.toggle", { page: page }, function (ok, err) { if (err) { asked = ""; by = "" } })
    }
    // Opens the card on `page` and never closes it (a hover: what is open stays).
    function show(page, who) {
        if (cardOpen && shown === page) { by = who; return }
        open(page, who)
    }
    // The card takes the page it was asked for (once).
    function take() {
        var p = asked
        asked = ""
        return p
    }
    // The card shows `page`; `asked` whether a module's ask turned it there (else the card did, by its tiles or Back:
    // no module opened that).
    function showing(page, asked) {
        shown = page
        if (!asked) by = ""
    }
}
