import QtQuick
import "../../../core"

// Fluent (W53.3): Windows 11's slider (WinUI Slider_themeresources: SliderTrackThemeHeight 4, SliderTrackCornerRadius 2,
// SliderHorizontalThumbWidth/Height 18 with SliderThumbCornerRadius 10, SliderInnerThumbWidth/Height 12) — a 4 px rail
// in the strong control ink, the value's part in the accent, and the thumb: an 18 px circle in the solid control fill
// with a hairline, round an accent dot of 12 px that grows to 14 under the pointer and shrinks to 10 while dragged.
// Static at rest; the dot's size eases on the fast curve while the pointer is on it.
SliderBase {
    id: sl
    property bool hovered: false
    readonly property real v: Math.max(0, Math.min(1, value))
    readonly property int knob: 18
    readonly property real span: (vertical ? height : width) - knob

    Rectangle {
        x: sl.vertical ? Math.round((sl.width - 4) / 2) : sl.knob / 2
        y: sl.vertical ? sl.knob / 2 : Math.round((sl.height - 4) / 2)
        width: sl.vertical ? 4 : sl.span
        height: sl.vertical ? sl.span : 4
        radius: 2
        color: Qt.alpha(Theme.fg, Theme.darkScheme ? 0.55 : 0.45)
        Rectangle {
            width: sl.vertical ? parent.width : parent.width * sl.v
            height: sl.vertical ? parent.height * sl.v : parent.height
            y: sl.vertical ? parent.height - height : 0
            radius: 2
            color: Theme.accent
        }
    }
    Rectangle {
        id: thumb
        width: sl.knob
        height: sl.knob
        radius: sl.knob / 2
        x: sl.vertical ? Math.round((sl.width - sl.knob) / 2) : Math.round(sl.span * sl.v)
        y: sl.vertical ? Math.round(sl.span * (1 - sl.v)) : Math.round((sl.height - sl.knob) / 2)
        // ControlSolidFillColorDefault: white on light, #454545 on dark — the control fill a step up.
        color: Qt.lighter(Theme.containerHigh, Theme.darkScheme ? 1.25 : 1.01)
        border.width: 1
        border.color: Qt.alpha(Theme.fg, 0.1)
        Rectangle {
            property real d: sl.pressed ? 10 : (sl.hovered ? 14 : 12)
            anchors.centerIn: parent
            width: d
            height: d
            radius: d / 2
            color: Theme.accent
            Behavior on d {
                enabled: Theme.timed
                NumberAnimation { duration: Theme.fastMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.fastCurve }
            }
        }
    }
}
