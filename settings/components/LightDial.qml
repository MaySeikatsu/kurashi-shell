import QtQuick
import QtQuick.Shapes
import "../core"

// Under Light (K59, docs/ux/texture.md "Settings"): where the material's light comes from. For a fixed light (and the
// pointer's resting light) a dial — a lit dome you drag: the angle round it is the direction, the distance from the
// middle the height (the middle is high, the rim low) — with the numbers beside it; arrows turn it by 15°, Up/Down
// raise or lower it by 5°, and a release or key press is one change (both keys, one undo step). For the sun and the
// wallpaper's light, the daemon's words for where it is now (`theme.appearance.light_detail`) and its direction in
// effect (`light.dir`).
Row {
    id: ld
    readonly property string mode: Store.valueOf("theme.light.mode") || "static"
    readonly property string detail: (Store.theme && Store.theme.appearance && Store.theme.appearance.light_detail) || ""
    readonly property bool fixed: ld.mode === "static" || ld.mode === "pointer"
    readonly property real angle: ld.dragging ? ld.dragAngle : Number(Store.valueOf("theme.light.angle") ?? 315)
    readonly property real elevation: ld.dragging ? ld.dragElevation : Number(Store.valueOf("theme.light.elevation") ?? 40)
    // The direction in effect, as the daemon resolved it (the sun's for daytime): compass degrees and height.
    readonly property var dir: Theme.tokens["light.dir"] || [0, -0.7, 0.7]
    readonly property real shownAngle: ld.fixed ? ld.angle : ((Math.atan2(ld.dir[0], -ld.dir[1]) * 180 / Math.PI) + 360) % 360
    readonly property real shownElevation: ld.fixed ? ld.elevation : Math.asin(Math.max(-1, Math.min(1, ld.dir[2]))) * 180 / Math.PI
    property bool dragging: false
    property real dragAngle: 0
    property real dragElevation: 40
    // The test hook: the line as shown.
    readonly property string text: note.text

    function commit(a, e) {
        a = ((Math.round(a) % 360) + 360) % 360
        e = Math.max(10, Math.min(80, Math.round(e)))
        Store.apply([{ set: "theme.light.angle", value: a }, { set: "theme.light.elevation", value: e }])
    }
    function fromPoint(x, y) {
        var r = dial.width / 2, dx = x - r, dy = y - r
        var d = Math.min(1, Math.sqrt(dx * dx + dy * dy) / r)
        ld.dragAngle = ((Math.atan2(dx, -dy) * 180 / Math.PI) + 360) % 360
        ld.dragElevation = 80 - d * 70
    }

    width: parent ? parent.width : 480
    spacing: Theme.pad
    objectName: "light-dial"

    Item {
        id: dial
        visible: Theme.tokens["texture.map"] !== undefined
        width: 96
        height: 96
        activeFocusOnTab: ld.fixed
        opacity: Store.live && ld.fixed ? 1 : 0.75
        Keys.onLeftPressed: event => { ld.commit(ld.angle - 15, ld.elevation); event.accepted = true }
        Keys.onRightPressed: event => { ld.commit(ld.angle + 15, ld.elevation); event.accepted = true }
        Keys.onUpPressed: event => { ld.commit(ld.angle, ld.elevation + 5); event.accepted = true }
        Keys.onDownPressed: event => { ld.commit(ld.angle, ld.elevation - 5); event.accepted = true }
        Accessible.role: Accessible.Dial
        Accessible.name: I18n.fmt("settings.light.dial", { angle: Math.round(ld.shownAngle), elevation: Math.round(ld.shownElevation) })

        // The dome, lit from the light: the highlight sits toward it, nearer the rim the lower the light.
        readonly property real reach: (90 - ld.shownElevation) / 90 * 0.42
        readonly property real hx: 0.5 + Math.sin(ld.shownAngle * Math.PI / 180) * reach
        readonly property real hy: 0.5 - Math.cos(ld.shownAngle * Math.PI / 180) * reach
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 1
                strokeColor: Theme.outline
                fillGradient: RadialGradient {
                    centerX: dial.width * dial.hx
                    centerY: dial.height * dial.hy
                    centerRadius: dial.width * 0.75
                    focalX: centerX
                    focalY: centerY
                    GradientStop { position: 0; color: Qt.lighter(Theme.containerHigh, 1.6) }
                    GradientStop { position: 0.55; color: Theme.containerHigh }
                    GradientStop { position: 1; color: Qt.darker(Theme.containerHigh, 1.5) }
                }
                PathAngleArc { centerX: dial.width / 2; centerY: dial.height / 2; radiusX: dial.width / 2 - 1; radiusY: dial.height / 2 - 1; startAngle: 0; sweepAngle: 360 }
            }
        }
        // The light itself: a small sun on its bearing, nearer the middle the higher it stands.
        Rectangle {
            readonly property real d: (80 - Math.max(10, Math.min(80, ld.shownElevation))) / 70 * (dial.width / 2 - 8)
            x: dial.width / 2 + Math.sin(ld.shownAngle * Math.PI / 180) * d - width / 2
            y: dial.height / 2 - Math.cos(ld.shownAngle * Math.PI / 180) * d - height / 2
            width: 12
            height: 12
            radius: 6
            color: Theme.tokens["light.color"] || "#ffffff"
            border.width: 2
            border.color: Theme.accent
        }
        MouseArea {
            anchors.fill: parent
            enabled: Store.live && ld.fixed
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => { ld.fromPoint(mouse.x, mouse.y); ld.dragging = true }
            onPositionChanged: mouse => { if (ld.dragging) ld.fromPoint(mouse.x, mouse.y) }
            onReleased: { ld.dragging = false; ld.commit(ld.dragAngle, ld.dragElevation) }
            onCanceled: ld.dragging = false
        }
        FocusRing {
            anchors.fill: parent
            shown: dial.activeFocus
            corner: width / 2
        }
    }
    Column {
        width: ld.width - (dial.visible ? dial.width + ld.spacing : 0)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Text {
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.fmt("settings.light.numbers", { angle: Math.round(ld.shownAngle), elevation: Math.round(ld.shownElevation) })
        }
        Text {
            id: note
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs - 1
            font.family: Theme.fam(text, Theme.families)
            text: ld.mode === "pointer" ? I18n.tr("settings.light.pointer")
                : ld.mode === "daytime" ? I18n.tr("settings.light.daytime." + (ld.detail || "day"))
                : ld.mode === "wallpaper" ? I18n.tr("settings.light.wallpaper." + (ld.detail || "wallpaper_waiting"))
                : I18n.tr("settings.light.static")
        }
    }
}
