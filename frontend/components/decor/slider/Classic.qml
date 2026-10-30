import QtQuick
import "../../../core"
import ".."

// Classic (W53.1): a bevel-era trackbar — a 4 px sunken groove along the middle and a raised 11 × 21 thumb (21 × 11 on a
// vertical one) at `value`, sunk while dragged; the fill is not coloured (9x's trackbar had none). Static.
SliderBase {
    id: sl
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property int tw: vertical ? 21 : 11
    readonly property int th: vertical ? 11 : 21
    Item {
        x: sl.vertical ? Math.round((sl.width - 4) / 2) : sl.tw / 2
        y: sl.vertical ? sl.th / 2 : Math.round((sl.height - 4) / 2)
        width: sl.vertical ? 4 : sl.width - sl.tw
        height: sl.vertical ? sl.height - sl.th : 4
        Rectangle { anchors.fill: parent; color: Theme.surface }
        BevelEdge { anchors.fill: parent; w: sl.hair; sunk: true; dark: Theme.bevelDark2; dark2: Theme.bevelDark }
    }
    Item {
        width: sl.tw
        height: sl.th
        x: sl.vertical ? Math.round((sl.width - sl.tw) / 2) : Math.round((sl.width - sl.tw) * Math.max(0, Math.min(1, sl.value)))
        y: sl.vertical ? Math.round((sl.height - sl.th) * (1 - Math.max(0, Math.min(1, sl.value)))) : Math.round((sl.height - sl.th) / 2)
        Rectangle { anchors.fill: parent; color: Theme.surface }
        BevelEdge { anchors.fill: parent; w: sl.hair; sunk: sl.pressed }
    }
}
