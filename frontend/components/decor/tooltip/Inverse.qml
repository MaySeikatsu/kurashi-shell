import QtQuick
import "../../../core"

// Inverse (W53.8, docs/ux/styles.md "terminal"): a tooltip as an inverse-video line — the text's ink as the ground
// (`[decor] tooltip.fill`, else the text role) with the ground's colour as the text (`tooltip.on`, the caller's ink), square,
// no border, no shadow: a terminal's status message (tmux's message line, a reverse-video curses label). Roles only
// (rule 4); static.
TooltipBase {
    id: tt
    readonly property string fill: Theme.decor("tooltip.fill", "")
    Rectangle {
        anchors.fill: parent
        antialiasing: false
        radius: Math.max(0, Theme.decor("tooltip.radius", -1))
        color: tt.fill !== "" ? tt.fill : Theme.fg
    }
}
