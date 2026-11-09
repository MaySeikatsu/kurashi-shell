import QtQuick
import "../modules" as M

// One module of a bar's zone (ModuleHost), told where it stands by its bar (surfaces/Bar.qml): its edge and thickness,
// its output, whether the bar is out (`live`), whether it registers the Stage's origins (the output's primary bar), the
// bar's link; a busy module (a menu or a drag open) holds a hover-revealed bar out. On a top or bottom bar the bar's fit
// (B48, components/bar/barfit.js) sets its `compact`, `room` and `parked`.
M.ModuleHost {
    id: zh
    required property var owner
    thickness: owner.barH
    vertical: owner.vertical
    edge: owner.edge
    output: owner.outName
    screen: owner.scr
    // (a module in the overflow is not live on the bar: the overflow's card hosts it while open, B48)
    live: owner.shownAmt > 0 && !parked
    anchored: owner.primary
    link: owner.link
    // What the module says for the fit changed: the bar lays its row out again (on the next turn, once).
    onFitKeyChanged: owner.requestFit()
    onShownChanged: owner.requestFit()
    onTrayMenuRequested: id => owner.trayMenuRequested(id)
    onBusyChanged: owner.link.hold("host:" + zh.mid, busy)
    Component.onDestruction: owner.link.hold("host:" + zh.mid, false)
}
