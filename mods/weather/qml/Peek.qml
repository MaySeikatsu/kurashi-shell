import QtQuick
import qs.core
import qs.components
import "Weather.js" as W

// The weather peek (docs/ux/weather.md §5): the place, feels-like, high and low, "rain from", the age of the data, and why
// there is no fresh data, in words. The Stage draws it on hover or keyboard focus of the bar widget (K35). It reads the
// mod's document only while it shows (Ma). With no place it says so, as the widget's label does.
PeekLines {
    id: peek
    // Handed in by ModLoader (K26); the core singletons are imported too.
    required property var store
    required property var theme
    required property var i18n
    Watch { doc: "mod.weather" }

    readonly property var d: Store.docs["mod.weather"] || ({})
    readonly property bool loaded: Store.docs["mod.weather"] !== undefined
    readonly property bool hasPlace: d.reason !== "mod-weather.no_location"
    readonly property bool ok: d.available === true
    readonly property var now: d.now || ({})
    readonly property bool hasNow: ok && d.now !== undefined
    readonly property string tier: d.tier || ""
    readonly property bool veryStale: tier === "very_stale"
    readonly property string placeName: d.place ? d.place.name : ""
    readonly property int savedCount: (d.places || []).length
    readonly property string ageText: {
        var p = W.ageParts(d.age_s)
        return p.n > 0 ? W.fill(I18n.tr(p.key), { n: p.n }) : I18n.tr(p.key)
    }

    lines: {
        if (!loaded) return [I18n.tr("mod-weather.loading")]
        if (!hasPlace) return [I18n.tr("mod-weather.set_place")]
        var out = []
        if (placeName !== "") out.push(placeName)
        if (hasNow) out.push(W.fill(I18n.tr("mod-weather.feels"), { temp: W.deg(now.feels) }))
        var day = d.days && d.days.length > 0 ? d.days[0] : null
        if (day) out.push(W.fill(I18n.tr("mod-weather.high_low"), { max: W.deg(day.max), min: W.deg(day.min) }))
        if (d.rain_soon) out.push(W.fill(I18n.tr("mod-weather.rain_from"), { time: W.hm(d.rain_soon.from) }))
        if (veryStale) {
            out.push(W.fill(I18n.tr("mod-weather.very_stale"), { time: W.hm(d.updated_local) }))
        } else {
            if (ok && d.updated_local) out.push(W.fill(I18n.tr("mod-weather.updated"), { age: ageText }))
            if (tier === "stale") out.push(I18n.tr("mod-weather.tier.stale"))
        }
        if (d.reason) {
            out.push(I18n.tr(d.reason))
            if (d.next_try_s !== undefined) out.push(W.fill(I18n.tr("mod-weather.next_try"), { n: Math.max(1, Math.ceil(d.next_try_s / 60)) }))
        }
        // Scrolling only changes place when there is a choice.
        if (savedCount > 1) out.push(I18n.tr("mod-weather.scroll_hint"))
        return out
    }
}
