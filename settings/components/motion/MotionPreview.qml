import QtQuick
import "../../core"
import ".."

// PLACEHOLDER (W59.6, waiting on W59.2): the Motion page's preview stage (brief §8 item 1) — a miniature bar over a
// patterned ground with a button per surface class; a click (or Space) opens that surface's sample card with the current
// settings through the frontend's own components/motion (FormHost, Driver: the same forms, not copies); Slow 1× · ½× · ¼×;
// a scrubber on Driver.track (p 0 → 1); Compare (hold) plays the previous value. It plays on change and on demand only and
// stops while the window is hidden (Ma). Until W59.2 merges this says what will be here and draws nothing that moves.
RoundBox {
    id: pv
    objectName: "motion-preview"
    implicitHeight: col.implicitHeight + 2 * Theme.pad
    radius: Theme.rSm
    color: Theme.containerHigh
    border.width: 1
    border.color: Theme.outline
    Accessible.role: Accessible.Grouping
    Accessible.name: I18n.tr("motion.ui.preview.title")

    Column {
        id: col
        x: Theme.pad
        y: Theme.pad
        width: parent.width - 2 * Theme.pad
        spacing: Theme.gap / 2
        MotionText { width: parent.width; font.weight: Font.DemiBold; text: I18n.tr("motion.ui.preview.title") }
        MotionText { width: parent.width; small: true; color: Theme.dim; text: I18n.tr("motion.ui.preview.pending") }
    }
}
