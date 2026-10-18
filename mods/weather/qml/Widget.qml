import QtQuick
import qs.core
import qs.components
import "Weather.js" as W

// Bar widget of the weather mod (docs/ux/weather.md, Design): the glyph and temperature in the
// template the user set. Stale data is dimmed, and the peek (Peek.qml, K35) names its age and tier, so
// the state is never colour alone. No place, loading, offline and very stale are named in words, never shown as
// 0 degrees (Shōjiki). With no place, a click opens the place setting (K32); otherwise a click opens
// the panel, middle click asks for a refresh (the daemon allows one a minute) and scroll moves to the
// next saved place. Visible = subscribed (Ma): hidden, it holds nothing.
Item {
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n
    id: w

    property bool live: visible
    Watch { doc: "mod.weather"; active: w.live }

    readonly property var d: Store.docs["mod.weather"] || ({})
    readonly property bool loaded: Store.docs["mod.weather"] !== undefined
    readonly property bool hasPlace: d.reason !== "mod-weather.no_location"
    readonly property bool ok: d.available === true
    readonly property var now: d.now || ({})
    readonly property bool hasNow: ok && d.now !== undefined
    readonly property string tier: d.tier || ""
    readonly property bool veryStale: tier === "very_stale"
    readonly property bool dim: tier === "stale" || veryStale
    readonly property string placeName: d.place ? d.place.name : ""
    readonly property int savedCount: (d.places || []).length
    // The state in words for the accessible name: the place's last value, its age, or why there is none.
    readonly property string stateText: veryStale
        ? W.fill(I18n.tr("mod-weather.very_stale"), { time: W.hm(d.updated_local) })
        : I18n.tr(d.reason || "mod-weather.loading")

    readonly property string label: {
        if (!loaded) return "…"
        if (!hasPlace) return I18n.tr("mod-weather.set_place")
        if (!ok) return d.reason === "mod-weather.loading" ? "…" : "—"
        if (!hasNow) return "—"
        return W.fill(d.template || "{glyph} {temp}", {
            glyph: W.glyph(now.code, now.is_day),
            temp: W.deg(now.temp),
            feels: W.deg(now.feels)
        })
    }

    readonly property string ageText: {
        var p = W.ageParts(d.age_s)
        return p.n > 0 ? W.fill(I18n.tr(p.key), { n: p.n }) : I18n.tr(p.key)
    }

    function openPanel() {
        Store.act("mod.panel.open", { id: "weather", panel: "weather" })
    }

    // The primary action: with no place there is nothing to show, so it opens the place setting (K32);
    // otherwise the panel.
    function primary() {
        if (w.loaded && !w.hasPlace) Store.act("settings.open", { key: "mods.weather.place" })
        else w.openPanel()
    }

    // The daemon allows one manual refresh a minute. The panel shows the wait after a refresh; the widget keeps no countdown.
    function refresh() {
        Store.act("weather.refresh", {})
    }

    implicitWidth: label_t.implicitWidth + Theme.gap * 2
    implicitHeight: Theme.controlH
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: !loaded ? I18n.tr("mod-weather.loading")
        : !hasPlace ? I18n.tr("mod-weather.a11y.widget_none")
        : hasNow
            ? W.fill(I18n.tr("mod-weather.a11y.widget"), { place: placeName, temp: W.deg(now.temp), condition: I18n.tr("mod-weather.condition." + now.code), age: ageText })
            : W.fill(I18n.tr("mod-weather.a11y.widget_state"), { place: placeName, state: stateText })

    Keys.onReturnPressed: w.primary()
    Keys.onEnterPressed: w.primary()
    Keys.onSpacePressed: w.primary()

    Text {
        id: label_t
        anchors.centerIn: parent
        text: w.label
        color: Theme.fg
        opacity: w.dim ? Theme.staleOpacity : 1
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
    }

    FocusRing { anchors.fill: parent; shown: w.activeFocus; corner: Theme.rSm }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function (mouse) {
            if (mouse.button === Qt.MiddleButton) w.refresh()
            else w.primary()
        }
        onWheel: function (wheel) {
            // One saved place per wheel notch (120 units), not per pixel of a touchpad swipe.
            if (Math.abs(wheel.angleDelta.y) >= 120) Store.act("weather.place.next", {})
            wheel.accepted = true
        }
    }

}
