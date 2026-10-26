import QtQuick
import "../../core"

// Module `clock`: the time (svc.clock) as hours and minutes, on one line in a row, on two in a column (the text is never
// turned). The daemon ticks once a minute; nothing here runs a timer (Ma).
ModuleBase {
    id: m
    Watch { doc: "svc.clock"; active: m.live }
    readonly property var clock: Store.docs["svc.clock"] || ({})
    width: vertical ? thickness : t.implicitWidth
    height: t.implicitHeight
    // The two lines' height, measured on a text that does not change: a hidden Text is not laid out, so its own implicit
    // height would follow the fit it feeds (a binding loop).
    TextMetrics { id: clockM; text: "00"; font.pixelSize: Theme.fs; font.family: Theme.fam(text, Theme.families) }
    slotHeights: [vertical ? 2 * clockM.height : height]
    function geo() { return [["clock", m]] }
    Text {
        id: t
        width: m.vertical ? m.thickness : implicitWidth
        horizontalAlignment: m.vertical ? Text.AlignHCenter : Text.AlignLeft
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.weight: m.vertical ? Font.Normal : Theme.wBold
        font.family: Theme.fam(text, Theme.families)
        text: (m.clock.hh ?? "--") + (m.vertical ? "\n" : ":") + (m.clock.mm ?? "--")
    }
}
