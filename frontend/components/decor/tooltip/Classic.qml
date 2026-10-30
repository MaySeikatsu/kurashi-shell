import QtQuick
import "../../../core"

// Classic (W53.1): a bevel-era tooltip — InfoWindow yellow (`[decor] tooltip.fill`, the `info` role; measured #ffffe1 on
// 98's Start menu) in a 1 px black frame, square, no shadow and no tail (balloons came later). The caller's text takes
// `tooltip.on`. Static.
TooltipBase {
    id: tt
    readonly property string fill: Theme.decor("tooltip.fill", "")
    Rectangle {
        anchors.fill: parent
        color: tt.fill !== "" ? tt.fill : Theme.color("color.info", "#ffffe1")
        border.width: Theme.crisp(1, Screen.devicePixelRatio)
        border.color: Theme.bevelDark
    }
}
