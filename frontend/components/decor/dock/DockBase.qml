import QtQuick
import "../../../core"

// The contract of a dock body (`[slots] dock`, W53.4): drawn under the dock's icons, filling its floating body. `edge`
// is the screen edge the dock stands on ("bottom", "left", "right", "top"); `mirror` the icon list a part may reflect
// (`[decor] dock.reflection`; null = none) and `icon` its icons' size (the icons stand at the list's top, a bottom dock's
// shelf begins under them). Reads `[decor] dock.fill` (one role solid, two a gradient) and `dock.radius`.
Item {
    property string edge: "bottom"
    property Item mirror: null
    property real icon: 0
    readonly property bool vertical: edge === "left" || edge === "right"
}
