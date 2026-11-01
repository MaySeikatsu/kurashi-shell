import QtQuick
import "../../../core"
import "../.."

// Keycap (W53.7, docs/ux/styles.md §9 sekai, K42): a tooltip — and a toast, drawn as the look's tooltip — as a small
// key: one Block in the keycap chrome (ink outline, white ring, the hard shadow under it), its face the light container,
// corners the look's small radius. Roles only (rule 4); static.
TooltipBase {
    id: tt
    readonly property string fill: Theme.decor("tooltip.fill", "")
    Block {
        anchors.fill: parent
        fill: tt.fill !== "" ? tt.fill : Theme.containerHigh
        radius: Math.min(Theme.rLg, (height - Theme.shadowDy) / 2)
        animate: false
        penSeed: 0x5E7B
    }
}
