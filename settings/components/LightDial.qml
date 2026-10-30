import QtQuick
import QtQuick.Shapes
import "../core"

// Under Light (K59, K61, docs/ux/texture.md "Settings" and "The spotlight"): where the material's light comes from. For a
// fixed light (the pointer's resting light, and the spotlight's direction and height) a dial — a lit dome you drag: the
// angle round it is the direction, the distance from the middle the height (the middle is high, the rim low) — with the
// numbers beside it; arrows turn it by 15°, Up/Down raise or lower it by 5°, and a release or key press is one change
// (both keys, one undo step). In spotlight mode a little screen beside the dial shows where the lamp is pinned (the
// daemon's `light.pin`: where the light's direction meets the screen's edge) and its beam (`theme.light.beam`) resting on
// the middle; a click on that screen moves the pin there (the direction only). For the sun and the wallpaper's light,
// the daemon's words for where it is now (`theme.appearance.light_detail`) and its direction in effect (`light.dir`).
Row {
    id: ld
    readonly property string mode: Store.valueOf("theme.light.mode") || "static"
    readonly property string detail: (Store.theme && Store.theme.appearance && Store.theme.appearance.light_detail) || ""
    readonly property bool spotlight: ld.mode === "spotlight"
    readonly property bool fixed: ld.mode === "static" || ld.mode === "pointer" || ld.spotlight
    readonly property real angle: ld.dragging ? ld.dragAngle : Number(Store.valueOf("theme.light.angle") ?? 315)
    readonly property real elevation: ld.dragging ? ld.dragElevation : Number(Store.valueOf("theme.light.elevation") ?? 40)
    readonly property real beam: Number(Store.valueOf("theme.light.beam") ?? 35)
    // The direction in effect, as the daemon resolved it (the sun's for daytime): compass degrees and height.
    readonly property var dir: Theme.tokens["light.dir"] || [0, -0.7, 0.7]
    readonly property real shownAngle: ld.fixed ? ld.angle : ((Math.atan2(ld.dir[0], -ld.dir[1]) * 180 / Math.PI) + 360) % 360
    readonly property real shownElevation: ld.fixed ? ld.elevation : Math.asin(Math.max(-1, Math.min(1, ld.dir[2]))) * 180 / Math.PI
    // The pin as fractions of the screen: the daemon's while nothing is dragged, else the same rule
    // (kurashi_texture::pin) for the angle under the pointer.
    readonly property var pin: {
        var t = Theme.tokens["light.pin"]
        if (!ld.dragging && Array.isArray(t) && t.length === 2) return t
        var a = ld.shownAngle * Math.PI / 180, ux = Math.sin(a), uy = -Math.cos(a)
        var m = Math.max(Math.abs(ux), Math.abs(uy), 1e-6)
        return [0.5 + 0.5 * ux / m, 0.5 + 0.5 * uy / m]
    }
    readonly property color lightColor: Theme.tokens["light.color"] || "#ffffff"
    property bool dragging: false
    property real dragAngle: 0
    property real dragElevation: 40
    // The test hook: the line as shown.
    readonly property string text: note.text
    readonly property string reachText: reach.visible ? reach.text : ""

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
    // A point on the little screen: the direction from its middle, in fractions (so a corner is 45° on any shape).
    function fromScreen(x, y) {
        var dx = x / stage.width - 0.5, dy = y / stage.height - 0.5
        if (Math.abs(dx) < 0.02 && Math.abs(dy) < 0.02) return
        ld.dragAngle = ((Math.atan2(dx, -dy) * 180 / Math.PI) + 360) % 360
        ld.dragElevation = ld.elevation
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
            color: ld.lightColor
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

    // The spotlight on a little screen (16:9): the pin on the edge, the beam resting on the middle, its pool as wide as
    // the beam. Display and pointer only — the dial beside it is the keyboard's way to move the same light.
    Item {
        id: stage
        objectName: "light-screen"
        visible: dial.visible && ld.spotlight
        width: 144
        height: 81
        anchors.verticalCenter: parent.verticalCenter
        Accessible.role: Accessible.Graphic
        Accessible.name: I18n.fmt("settings.light.screen", { angle: Math.round(ld.shownAngle), beam: Math.round(ld.beam) })
        readonly property real px: ld.pin[0] * width
        readonly property real py: ld.pin[1] * height
        // From the pin to the middle; the beam's half width there.
        readonly property real len: Math.max(1, Math.sqrt(Math.pow(width / 2 - px, 2) + Math.pow(height / 2 - py, 2)))
        readonly property real half: len * Math.tan(Math.max(10, Math.min(80, ld.beam)) / 2 * Math.PI / 180)
        // The unit normal to the beam's axis.
        readonly property real nx: -(height / 2 - py) / len
        readonly property real ny: (width / 2 - px) / len

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: Qt.darker(Theme.containerHigh, 1.25)
            border.width: 1
            border.color: Theme.outline
            clip: true
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                // The beam: from the lamp out to the middle, then its pool there.
                ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillGradient: LinearGradient {
                        x1: stage.px; y1: stage.py
                        x2: stage.width / 2; y2: stage.height / 2
                        GradientStop { position: 0; color: Qt.alpha(ld.lightColor, 0.75) }
                        GradientStop { position: 1; color: Qt.alpha(ld.lightColor, 0.35) }
                    }
                    startX: stage.px; startY: stage.py
                    PathLine { x: stage.width / 2 + stage.nx * stage.half; y: stage.height / 2 + stage.ny * stage.half }
                    PathLine { x: stage.width / 2 - stage.nx * stage.half; y: stage.height / 2 - stage.ny * stage.half }
                    PathLine { x: stage.px; y: stage.py }
                }
                ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillColor: Qt.alpha(ld.lightColor, 0.35)
                    PathAngleArc {
                        centerX: stage.width / 2; centerY: stage.height / 2
                        radiusX: stage.half; radiusY: stage.half
                        startAngle: 0; sweepAngle: 360
                    }
                }
            }
        }
        // The lamp on its pin.
        Rectangle {
            x: stage.px - width / 2
            y: stage.py - height / 2
            width: 12
            height: 12
            radius: 6
            color: ld.lightColor
            border.width: 2
            border.color: Theme.accent
        }
        MouseArea {
            anchors.fill: parent
            enabled: Store.live
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => { ld.fromScreen(mouse.x, mouse.y); ld.dragging = true }
            onPositionChanged: mouse => { if (ld.dragging) ld.fromScreen(mouse.x, mouse.y) }
            onReleased: { ld.dragging = false; ld.commit(ld.dragAngle, ld.dragElevation) }
            onCanceled: ld.dragging = false
        }
    }

    Column {
        width: ld.width - (dial.visible ? dial.width + ld.spacing : 0) - (stage.visible ? stage.width + ld.spacing : 0)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: ld.spotlight
                ? I18n.fmt("settings.light.numbers_beam", { angle: Math.round(ld.shownAngle), elevation: Math.round(ld.shownElevation), beam: Math.round(ld.beam) })
                : I18n.fmt("settings.light.numbers", { angle: Math.round(ld.shownAngle), elevation: Math.round(ld.shownElevation) })
        }
        Text {
            id: note
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs - 1
            font.family: Theme.fam(text, Theme.families)
            text: ld.mode === "pointer" ? I18n.tr("settings.light.pointer")
                : ld.spotlight ? I18n.tr("settings.light.spotlight")
                : ld.mode === "daytime" ? I18n.tr("settings.light.daytime." + (ld.detail || "day"))
                : ld.mode === "wallpaper" ? I18n.tr("settings.light.wallpaper." + (ld.detail || "wallpaper_waiting"))
                : I18n.tr("settings.light.static")
        }
        // W58 (K79, Shōjiki): whether the lamp sees the pointer over windows too, or why it keeps to the shell's surfaces.
        Text {
            id: reach
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            readonly property var pdoc: Light.pointerDoc
            visible: (ld.mode === "pointer" || ld.spotlight) && text !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs - 1
            font.family: Theme.fam(text, Theme.families)
            text: !pdoc ? "" : pdoc.available === true ? I18n.tr("settings.light.everywhere")
                : I18n.tr(pdoc.reason || "pointer.no_protocol")
        }
    }
}
