import QtQuick

// The contract of a scroll bar part (`[slots] scroll`, W53.0a): the ScrollBar's whole visual — track, thumb and (with
// `[decor] scroll.arrows`) the arrows. `size` and `position` are the bar's (0..1); `step(±1)` asks the caller to scroll
// a line (the arrows act: no dead button).
Item {
    property real size: 1
    property real position: 0
    property int orientation: Qt.Vertical
    property bool pressed: false
    property bool hovered: false
    signal step(int direction)
}
