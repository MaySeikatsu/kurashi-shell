import QtQuick
import "../../core"

// Module `clock`: the time (svc.clock) as hours and minutes, on one line in a row, on two in a column (the text is never
// turned). The daemon ticks once a minute; nothing here runs a timer (Ma). K72 retrofit (I223, MODS.md "Modules"): its
// peek is ClockPeek (the day, the week, the next agenda item and timer), asked on hover or focus as the core source
// `clock:main`; its expanded view is the island's clock card (`island.expand {face: "clock"}`, Enter on the host's tab
// stop), as the calendar widget opens it.
ModuleBase {
    id: m
    Watch { doc: "svc.clock"; active: m.live }
    readonly property var clock: Store.docs["svc.clock"] || ({})
    // W53.3 (`[decor] clock.lines = 2`): on a horizontal bar the time over the short date, right-aligned, in the caption
    // size and regular weight (7–11's taskbar clock). The date is the daemon's; nothing more ticks.
    readonly property bool twoLines: !vertical && Theme.decor("clock.lines", 1) === 2
    readonly property string shortDate: {
        var d = clock.date ? new Date(clock.date + "T12:00:00") : null
        return d ? d.toLocaleDateString(Qt.locale((Store.docs["i18n"] || {}).locale || "en"), Locale.ShortFormat) : ""
    }
    width: vertical ? thickness : t.implicitWidth
    height: t.implicitHeight
    // The two lines' height, measured on a text that does not change: a hidden Text is not laid out, so its own implicit
    // height would follow the fit it feeds (a binding loop).
    TextMetrics { id: clockM; text: "00"; font.pixelSize: Theme.fs; font.family: Theme.fam(text, Theme.families) }
    slotHeights: [vertical ? 2 * clockM.height : height]
    function geo() { return [["clock", m]] }
    a11yName: clock.hh === undefined ? I18n.tr("layout.module.clock")
        : I18n.tr("edge-modules.clock.a11y").replace("{time}", clock.hh + ":" + clock.mm)
            .replace("{weekday}", clock.weekday || "").replace("{date}", clock.date || "")
    // Row 412: an island whose face list leaves the clock out refuses the face; its card then opens on the island's own.
    function activate() {
        Store.act("island.expand", { face: "clock" }, function (done, err) {
            if (err && err.kind === "invalid") Store.act("island.expand", {})
        })
    }
    Text {
        id: t
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        width: m.vertical ? m.thickness : implicitWidth
        horizontalAlignment: m.vertical ? Text.AlignHCenter : (m.twoLines ? Text.AlignRight : Text.AlignLeft)
        color: Theme.fg
        font.pixelSize: m.twoLines ? Theme.fsLabel : Theme.fs
        font.weight: m.vertical || m.twoLines ? Font.Normal : Theme.wBold
        font.family: Theme.fam(text, Theme.families)
        lineHeight: m.twoLines ? 1.15 : 1
        text: (m.clock.hh ?? "--") + (m.vertical ? "\n" : ":") + (m.clock.mm ?? "--")
            + (m.twoLines && m.shortDate !== "" ? "\n" + m.shortDate : "")
    }
    // The peek waits for the core source `clock:main` (CONTRACT-CHANGE row 550: kurashid's `ui.peek` accepts only mod, tray
    // and island sources, and the Stage draws only those). Until the lead takes the row, nothing is asked (no refused act
    // per hover); then this flag goes and the source stays.
    readonly property bool peekServed: false
    HoverHandler { id: hover; enabled: m.peekServed }
    // A click opens the expanded view, as Enter does (the glance → expanded path of every module, K72).
    TapHandler { onTapped: m.activate() }
    PeekSource {
        target: m
        source: m.peekServed ? "clock:main" : ""
        output: m.output
        hovered: hover.hovered
        focused: m.hostFocused
    }
}
