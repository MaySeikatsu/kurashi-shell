import QtQuick
import qs.core
import "../Weather.js" as W

// Day mark (K28 slot `clock.expanded.daymark`, row 71; docs/ux/weather.md "Clock view integration"): the forecast glyph
// under the number of each day the month grid shows that `mod.weather.days` covers, and nothing for any other date. The
// host gives `date` (yyyy-mm-dd, the cell's local date) on each load and whenever it changes. A day with no mark takes no
// room, so the marks of a day sit where they would sit alone. A stale forecast is dimmed (Shōjiki).
Item {
    id: mark
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n
    property string date: ""

    property bool live: visible
    Watch { doc: "mod.weather"; active: mark.live }

    readonly property var d: Store.docs["mod.weather"] || ({})
    readonly property bool ok: d.available === true
    readonly property bool stale: ok && (d.tier === "stale" || d.tier === "very_stale")
    // The forecast of this date, or null when the forecast does not cover it.
    readonly property var day: {
        if (!ok || !d.days || date === "") return null
        for (var i = 0; i < d.days.length; i++) {
            if (d.days[i].date === date) return d.days[i]
        }
        return null
    }

    implicitWidth: day !== null ? 14 : 0
    implicitHeight: 14
    Accessible.role: Accessible.StaticText
    Accessible.name: day !== null ? I18n.tr("mod-weather.condition." + day.code) : ""

    Text {
        anchors.centerIn: parent
        visible: mark.day !== null
        text: mark.day !== null ? W.glyph(mark.day.code, true) : ""
        color: Theme.fg
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        opacity: mark.stale ? Theme.staleOpacity : 1
    }
}
