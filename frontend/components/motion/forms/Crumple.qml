import QtQuick

// crumple (W59.4, K83; docs/ux/motion-engine.md §5 — the user's crumbling paper; origami's toast close): closing, creases
// run across the sheet first (1 → 0.45), it balls up toward its middle (0.72 → 0.18), and the ball — about 18 % of the
// card's shorter side — leaves (0.3 → 0): into the origin it came from (the hinge's middle without one), or, for a toast,
// flicked off past the screen edge it came from, spinning. Opening is the same backwards: a ball comes out, opens, and
// its wrinkles smooth out last. Each card crumples its own way (the seed is the card's size) but always the same way.
// Params (`motion.form_params.crumple`): crumple 0–1 (how deep the creases go; 0.8).
SheetForm {
    id: cr

    readonly property real depth: params && params.crumple !== undefined ? Math.max(0, Math.min(1, params.crumple)) : 0.8
    readonly property bool flick: surface === "toast"
    readonly property real wrinkle: (1 - ease(sub(p, 0.45, 1))) * depth / 0.8
    readonly property real ball: 1 - ease(sub(p, 0.18, 0.72))
    readonly property real travel: 1 - ease(sub(p, 0, 0.3))

    readonly property point centre: Qt.point(area.width / 2, area.height / 2)
    readonly property real radius: Math.max(9, 0.09 * Math.min(area.width, area.height))
    // Where the ball goes: the origin's middle (item px of the capture), the hinge's middle, or off past the edge.
    readonly property point target: {
        if (flick) {
            var off = away / 2 + radius * 3
            return Qt.point(centre.x - axisD.x * off, centre.y - axisD.y * off)
        }
        if (origin.width > 0 || origin.height > 0)
            return Qt.point(origin.x + origin.width / 2 - area.x, origin.y + origin.height / 2 - area.y)
        return Qt.point(hinge.x + axisA.x * along / 2, hinge.y + axisA.y * along / 2)
    }
    // Along an arc (a toss, not a slide), faster as it goes; it shrinks into the origin and fades in its last third.
    readonly property point at: {
        var e = Math.pow(travel, 1.5)
        var dx = target.x - centre.x, dy = target.y - centre.y
        var hop = Math.sin(Math.PI * travel) * 0.14
        return Qt.point(centre.x + dx * e - dy * hop, centre.y + dy * e + dx * hop)
    }
    readonly property real scale: 1 - (flick ? 0.15 : 0.55) * travel
    readonly property real turn: 0.9 * ball + (flick ? 5 : 1.5) * travel

    SheetForm.Pass {
        host: cr
        name: "crumple"
        opacity: 1 - cr.smooth01((cr.travel - 0.65) / 0.35)
        mesh: GridMesh {
            resolution: Qt.size(Math.max(8, Math.min(64, Math.round(cr.area.width / 10))),
                                Math.max(6, Math.min(64, Math.round(cr.area.height / 10))))
        }
        u0: Qt.vector4d(cr.wrinkle, cr.ball, cr.travel, cr.turn)
        u1: Qt.vector4d(cr.at.x, cr.at.y, cr.radius, cr.scale)
        u2: Qt.vector4d(cr.centre.x, cr.centre.y, Math.hypot(cr.area.width, cr.area.height) / 2,
                        (Math.round(cr.area.width) * 7 + Math.round(cr.area.height) * 13) % 97 / 9.7)
    }
}
