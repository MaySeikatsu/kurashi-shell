import QtQuick
import "../../core"

// DockGround (W53.4, K80): the look's dock body (`[slots] dock`) — Mac OS X's translucent shelf, macOS 11+'s floating
// vibrancy panel — drawn by a part `decor/dock/<Name>.qml` (contract `dock/DockBase.qml`) from `[decor] dock.*`. The
// caller (the dock's floating body) fills it under its icons and tells it the screen edge (`edge`) and the icon list it
// may reflect (`mirror`, for `dock.reflection`); `tiles` says whether the icons keep a block each (`dock.tiles`) and
// `indicator` how a running app is marked (`dock.indicator`: dots · dot · triangle). Without a dock slot nothing is made
// and the caller keeps its own body (`has` false); the two metrics still apply. Static: one paint per size and colour.
DecorHost {
    id: dg
    slot: "dock"
    property string edge: "bottom"
    property Item mirror: null
    property real icon: 0
    readonly property bool tiles: Theme.decor("dock.tiles", "block") !== "none"
    readonly property string indicator: Theme.decor("dock.indicator", "dots")
    onLoaded: {
        item.edge = Qt.binding(function () { return dg.edge })
        item.mirror = Qt.binding(function () { return dg.mirror })
        item.icon = Qt.binding(function () { return dg.icon })
    }
}
