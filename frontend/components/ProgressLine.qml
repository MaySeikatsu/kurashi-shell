import QtQuick
import "../core"

// ProgressLine (I332): a determinate progress line (a track's position, the day gone) drawn as the look says
// (`[decor] progress.form`; data, rule 4): a pill — the fill grown along its track, today's — or Material 3's linear
// indicator (`m3`, m3.material.io/components/progress-indicators/specs): the active indicator, a 4 dp gap, the rest of
// the track in a lighter role, and a 4 dp stop indicator at the track's end while it is not full. Static: it changes only
// with `frac`.
Item {
    id: pl
    property real frac: 0
    property color fill: Theme.accent
    property color track: Qt.alpha(Theme.fg, 0.12)
    // An outline round the pill (keycap, line chrome); none under the M3 form.
    property real outlineWidth: 0
    property color outlineColor: Theme.line
    readonly property bool m3: Theme.decor("progress.form", "pill") === "m3"
    readonly property real f: Math.max(0, Math.min(1, frac))
    implicitHeight: 6

    Rectangle {
        visible: !pl.m3
        anchors.fill: parent
        radius: height / 2
        color: pl.track
        border.width: pl.outlineWidth
        border.color: pl.outlineColor
        Rectangle {
            x: pl.outlineWidth
            y: pl.outlineWidth
            height: parent.height - 2 * y
            width: pl.f > 0 ? Math.max(height, (parent.width - 2 * x) * pl.f) : 0
            radius: height / 2
            color: pl.fill
        }
    }
    Item {
        visible: pl.m3
        anchors.fill: parent
        readonly property real gap: 4
        readonly property real w: pl.f > 0 ? Math.max(height, width * pl.f) : 0
        Rectangle {
            width: parent.w
            height: parent.height
            radius: height / 2
            color: pl.fill
        }
        Rectangle {
            x: parent.w > 0 ? Math.min(pl.width, parent.w + parent.gap) : 0
            width: Math.max(0, pl.width - x)
            height: parent.height
            radius: height / 2
            color: Theme.color("color.accent_container", Qt.alpha(pl.fill, 0.24))
        }
        Rectangle {
            visible: pl.f < 1
            width: Math.min(4, pl.height)
            height: width
            radius: width / 2
            x: pl.width - width - (pl.height - width) / 2
            y: (pl.height - height) / 2
            color: pl.fill
        }
    }
}
