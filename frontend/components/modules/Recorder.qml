import QtQuick
import "../../core"

// Module `recorder` (K47, W23-system, docs/ux/power.md): a recording runs (svc.recorder) — a red dot and its label; a click
// stops it (`recorder.stop`). Absent while nothing records; the dot does not blink (no animation, Ma). In a column the dot
// stands over the label, both centred in the column's width (W36, I131).
ModuleBase {
    id: m
    Watch { doc: "svc.recorder"; active: m.live }
    present: (Store.docs["svc.recorder"] || ({})).recording === true
    width: vertical ? thickness : dotRow.implicitWidth + 2 * Theme.xs
    height: vertical ? thickness - 6 : thickness - 12
    slotHeights: present ? [height] : []
    Accessible.role: Accessible.Button
    Accessible.name: I18n.tr("power.bar.recording")
    a11yName: Accessible.name
    function activate() { Store.act("recorder.stop") }
    function geo() { return [["rec", m]] }
    Grid {
        id: dotRow
        anchors.centerIn: parent
        columns: m.vertical ? 1 : 2
        spacing: m.vertical ? 2 : Theme.xs
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        Rectangle {
            width: 10
            height: 10
            radius: 5
            color: Theme.error
        }
        Text {
            color: Theme.error
            font.pixelSize: Theme.fsCaption
            font.weight: Theme.wBold
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("power.bar.rec")
        }
    }
    TapHandler { onTapped: Store.act("recorder.stop") }
}
