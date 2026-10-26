import QtQuick
import "../modules" as M

// One module of a bar's zone (ModuleHost), told where it stands by its bar (surfaces/Bar.qml): its edge and thickness,
// its output, whether the bar is out (`live`), whether it registers the Stage's origins (the output's primary bar), the
// bar's link; a busy module (a menu or a drag open) holds a hover-revealed bar out.
M.ModuleHost {
    id: zh
    required property var owner
    thickness: owner.barH
    vertical: owner.vertical
    edge: owner.edge
    output: owner.outName
    screen: owner.scr
    live: owner.shownAmt > 0
    anchored: owner.primary
    link: owner.link
    onTrayMenuRequested: id => owner.trayMenuRequested(id)
    onBusyChanged: owner.link.hold("host:" + zh.mid, busy)
    Component.onDestruction: owner.link.hold("host:" + zh.mid, false)
}
