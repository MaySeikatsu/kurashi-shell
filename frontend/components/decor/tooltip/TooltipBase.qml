import QtQuick

// The contract of a tooltip background (`[slots] tooltip`, W53.0a): drawn under the tooltip's content, filling it; with
// a tail (`[decor] tooltip.tail`) it points to `tailSide` ("top", "bottom", "left", "right") at `tailAt` px along it.
Item {
    property string title: ""
    property string tailSide: "bottom"
    property real tailAt: width / 2
}
