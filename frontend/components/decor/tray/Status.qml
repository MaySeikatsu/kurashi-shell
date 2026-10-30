import QtQuick
import "../../../core"

// Status (W53.1): a status well — one line of the bevel's shadow along the top and left edges and one of its highlight along
// the bottom and right (9x's notification area and status-bar fields: `808080` over `ffffff`, measured from 98's taskbar),
// on the face. Lighter than a sunken field's two pairs; any bevel look can name it. Static (one paint per size and colour).
TrayBase {
    id: well
    readonly property real w: Theme.crisp(1, Screen.devicePixelRatio)
    Rectangle { anchors.fill: parent; color: Theme.surface }
    Rectangle { x: 0; y: 0; width: well.width; height: well.w; color: Theme.bevelDark2 }
    Rectangle { x: 0; y: 0; width: well.w; height: well.height; color: Theme.bevelDark2 }
    Rectangle { x: 0; y: well.height - well.w; width: well.width; height: well.w; color: Theme.bevelLight }
    Rectangle { x: well.width - well.w; y: 0; width: well.w; height: well.height; color: Theme.bevelLight }
}
