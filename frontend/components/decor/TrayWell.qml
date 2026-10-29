import QtQuick
import "../../core"

// TrayWell (W53.0a, K80): the well round the tray and the clock (`[slots] tray`; 9x's sunken notification area, XP's
// light-blue tray). The caller fills it over its tray group (anchors.fill) under the group's content. A look naming a
// tray part draws that (contract `tray/TrayBase.qml`); else, with `[decor] tray.sunken`, a sunken bevel; else nothing
// (today's group).
Item {
    id: tw
    property bool vertical: false
    readonly property bool shown: part.has || Theme.decor("tray.sunken", false) === true
    DecorHost {
        id: part
        slot: "tray"
        anchors.fill: parent
        onLoaded: item.vertical = Qt.binding(function () { return tw.vertical })
    }
    Loader {
        anchors.fill: parent
        active: !part.has && Theme.decor("tray.sunken", false) === true
        sourceComponent: BevelEdge {
            sunk: true
            w: Theme.crisp(1, Screen.devicePixelRatio)
        }
    }
}
