import QtQuick
import "../../../core"
import ".."

// Veil (W53.6, lead review): a word tab's start-menu skin without a box — Hollow Knight's floating menus (docs/ux/styles.md
// §9.4): the panel's ground as an oval veil that fades out toward every edge (one Canvas paint per size and colour), the
// look's caption rule (`[decor] title.rule`, an ornament) over it and under it in `title.rule_color`. No frame, no corner,
// no shadow. `start.skin = veil` names it. Colours from roles (rule 4); static.
StartMenuBase {
    id: sm
    readonly property string ruleRole: Theme.decor("title.rule_color", "")
    readonly property color ink: ruleRole !== "" ? ruleRole : Theme.fg
    Canvas {
        anchors.fill: parent
        property color ground: Theme.surface
        property real alpha: Math.max(0.85, Theme.tok("color.surface_alpha", 1))
        onGroundChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var g = getContext("2d")
            g.reset()
            if (width <= 0 || height <= 0) return
            g.save()
            g.translate(width / 2, height / 2)
            g.scale(width / 2, height / 2)
            var r = g.createRadialGradient(0, 0, 0, 0, 0, 1)
            var c = ground
            r.addColorStop(0, Qt.rgba(c.r, c.g, c.b, alpha))
            r.addColorStop(0.72, Qt.rgba(c.r, c.g, c.b, alpha * 0.92))
            r.addColorStop(1, Qt.rgba(c.r, c.g, c.b, 0))
            g.fillStyle = r
            g.fillRect(-1, -1, 2, 2)
            g.restore()
        }
    }
    Rule {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 2
        width: Math.min(parent.width - 24, 320)
        kind: Theme.decor("title.rule", "none")
        ink: sm.ink
        fade: kind === "single"
    }
    Rule {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - 2
        width: Math.min(parent.width - 24, 320)
        kind: Theme.decor("title.rule", "none")
        ink: sm.ink
        fade: kind === "single"
        transform: Scale { origin.y: 6; yScale: -1 }
    }
}
