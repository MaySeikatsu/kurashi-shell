import QtQuick

// The contract of a start-menu skin (W53 integration, contract row 563; K80 Decided 10): drawn by the launcher under its
// content while the look dresses a start button, filling the menu, in place of the launcher's own Block. The launcher
// keeps the search field, the rows (apps, commands, places as the daemon ranks them), their keys and the footer's
// session keys, and lays them inside the room the skin keeps for itself: `bandW` on the menu's left (9x's vertical
// banner), `headerH` on top (XP's user header) and `footerH` under the rows (the ground the session keys stand on; 0 =
// the launcher's own). `label` is the start button's (i18n `decor.start.label`), `edge` the bar's edge the menu hangs
// from ("bottom" or "top"). Static: paints once per size (0 frames idle).
Item {
    property string label: ""
    property bool open: false
    property string edge: "bottom"
    property real bandW: 0
    property real headerH: 0
    property real footerH: 0
}
