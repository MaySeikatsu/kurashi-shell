import QtQuick
import "../../../core"
import ".."

// Panel (W53.6): the start-menu skin of a word tab (`start/Tab`) — a game menu's panel rather than an OS's start menu:
// no banner, no header, no footer of its own; the panel's surface at the material's alpha, the look's ground pattern
// (NieR:Automata's faint grid) and its window frame (WindowEdge: a 1 px rule, or Needy Streamer Overload's violet–mint–
// violet band), square-cornered at the look's radius. The launcher keeps the search, the rows and the session keys.
// Colours from roles (rule 4); static (one paint per size).
StartMenuBase {
    id: sm
    readonly property real r: Theme.tok("shape.corner", "rounded") === "none" ? 0 : Theme.rSm
    Rectangle {
        anchors.fill: parent
        radius: sm.r
        color: Qt.alpha(Theme.surface, Math.max(0.85, Theme.tok("color.surface_alpha", 1)))
        Pattern { anchors.fill: parent; radius: sm.r }
    }
    WindowEdge { anchors.fill: parent; radius: sm.r }
}
