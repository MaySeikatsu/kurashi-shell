import QtQuick
import "../../../core"

// Plain (W53.8, docs/ux/styles.md "material"): Material 3's plain tooltip (material-web tokens md.comp.plain-tooltip, read
// 2026-11-01: container `inverse-surface`, shape corner-extra-small = 4 px, supporting text `inverse-on-surface` in body
// small) — no border, no tail. The fill is `[decor] tooltip.fill` (material's palette sets `info` to the inverse surface,
// `on_info` to its ink), the corner `tooltip.radius`. A toast drawn as this tooltip reads as M3's snackbar (the same
// inverse surface and 4 px corner). Static.
TooltipBase {
    id: tt
    readonly property string fill: Theme.decor("tooltip.fill", "")
    Rectangle {
        anchors.fill: parent
        radius: Math.max(0, Theme.decor("tooltip.radius", 4))
        color: tt.fill !== "" ? tt.fill : Theme.fg
    }
}
