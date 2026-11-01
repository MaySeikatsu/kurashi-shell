import QtQuick
import "../../../core"

// Plate (W53.6): a game's tooltip plate — a flat box of `[decor] tooltip.fill` at the material's alpha (a dark
// translucent panel under a translucent look: Dark Souls', Hollow Knight's; parchment under NieR:Automata's), a device-
// pixel hairline of `tooltip.border` round it ("" = none), `tooltip.radius` corners (-1 = square). No tail, no shadow;
// the caller's text takes `tooltip.on`. Colours from roles (rule 4); static.
TooltipBase {
    id: pl
    readonly property string fillRole: Theme.decor("tooltip.fill", "")
    readonly property string borderRole: Theme.decor("tooltip.border", "")
    Rectangle {
        anchors.fill: parent
        radius: Math.max(0, Theme.decor("tooltip.radius", -1))
        color: Qt.alpha(pl.fillRole !== "" ? pl.fillRole : Theme.surface, Math.max(0.85, Theme.tok("color.surface_alpha", 1)))
        border.width: pl.borderRole !== "" ? Theme.crisp(1, Screen.devicePixelRatio) : 0
        border.color: pl.borderRole !== "" ? pl.borderRole : "transparent"
    }
}
