import QtQuick
import qs.core
import qs.components
import "Weather.js" as W

// Bar widget of the weather mod (docs/ux/weather.md, Design): the glyph and temperature in the
// template the user set. Stale data is dimmed and the peek names its age and tier, so the state is
// never colour alone. No place, loading, offline and very stale are named in words, never shown as
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
    // Seconds the daemon asked us to wait before another manual refresh (middle click), counted down while visible.
    property int waitS: 0
    Timer {
        interval: 1000
        repeat: true
        running: w.live && w.waitS > 0
        onTriggered: w.waitS = Math.max(0, w.waitS - 1)
    }
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

    // The peek: one line per fact, the place first, then the second fact, the age and any failure.
    // Without a place there is nothing to peek at (the label already asks for one).
    readonly property var peekLines: {
        var out = []
        if (!loaded || !hasPlace) return out
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
        if (waitS > 0) out.push(W.fill(I18n.tr("mod-weather.refresh_wait"), { n: waitS }))
        // Scrolling only changes place when there is a choice.
        if (savedCount > 1) out.push(I18n.tr("mod-weather.scroll_hint"))
        return out
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

    function refresh() {
        Store.act("weather.refresh", {}, function (done, err) {
            if (done && done.data) w.waitS = done.data.started ? 0 : (done.data.retry_in_s || 0)
        })
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

    // Peek: shown on hover or keyboard focus, above the widget, one line per fact (Theme tokens only).
    property bool peekOpen: area.containsMouse || w.activeFocus
    Rectangle {
        id: peek
        // Fades in and out with the quick token (DESIGN-SYSTEM §9); invisible at 0, so it draws nothing.
        opacity: w.peekOpen && w.peekLines.length > 0 ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.quickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve }
        }
        z: 10
        anchors.bottom: parent.top
        anchors.bottomMargin: Theme.gap
        // Starts at the widget's left edge: a peek centred on a widget at the bar's edge would be clipped.
        anchors.left: parent.left
        width: Math.max(160, peekCol.implicitWidth + Theme.pad * 2)
        height: peekCol.implicitHeight + Theme.pad * 2
        radius: Theme.rSm
        color: Theme.containerHigh
        border.width: 1
        border.color: Theme.outline

        Column {
            id: peekCol
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: w.peekLines
                Text {
                    text: modelData
                    color: index === 0 ? Theme.fg : Theme.dim
                    font.pixelSize: index === 0 ? Theme.fs : Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                }
            }
        }
    }
}
