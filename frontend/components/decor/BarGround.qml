import QtQuick
import "../../core"

// BarGround (W53.2, K80): the look's ground under a bar (`[slots] bar`) — XP's glossy blue taskbar, 7's glass superbar —
// drawn by a part `decor/bar/<Name>.qml` (contract `bar/BarBase.qml`) from `[decor] bar.*`. The caller (the bar's strip)
// fills it under its groups and tells it the screen-facing edge (`edge`: "top" | "bottom" | "left" | "right", the side
// the bar stands on); `[decor] bar.group = none` asks the caller to draw its groups without a block of their own (a
// taskbar is one strip: `groups`). Without a bar slot nothing is made and the caller keeps its own ground (today's
// strip): `has` false. Static: one paint per size and colour.
DecorHost {
    id: bg
    slot: "bar"
    property string edge: "top"
    // The caller's groups keep their blocks over this ground (`[decor] bar.group = block`, the default).
    readonly property bool groups: !has || Theme.decor("bar.group", "block") !== "none"
    onLoaded: item.edge = Qt.binding(function () { return bg.edge })
}
