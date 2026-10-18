import QtQuick
import qs.core
import qs.components
import "Weather.js" as W

// Panel of the weather mod (docs/ux/weather.md, Design). The Stage card hosts it and draws the frame, so the
// panel draws none of its own: the header (place, age, refresh, places, settings), the states when there is no
// forecast to show, the hero, the chips with data only, the hourly strip, seven days on one shared scale, the sun
// row and the credit. The places mode searches the geocoder in the UI language, previews a result before it is
// saved, and moves and removes saved places; the top one is the default unless Settings names another. Every value
// is the daemon's; this file only maps and lays out.
Item {
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n
    id: p

    // Visible = open: the document is subscribed only while the panel can be seen (Ma).
    property bool live: visible
    Watch { doc: "mod.weather"; active: p.live }

    // The Stage card's outer width this panel asks for (contract row 66, I53: 360 to 720 px, and the output's
    // width). The card gives the panel its content width (the card less its margins); the panel lays out to it.
    property int cardWidth: 400
    width: parent.width
    implicitHeight: body.implicitHeight

    readonly property var d: Store.docs["mod.weather"] || ({})
    readonly property bool loaded: Store.docs["mod.weather"] !== undefined
    readonly property bool hasPlace: d.reason !== "mod-weather.no_location"
    readonly property bool noPlace: loaded && !hasPlace
    readonly property bool ok: d.available === true
    readonly property var now: d.now || ({})
    readonly property bool hasNow: ok && d.now !== undefined
    readonly property string tier: d.tier || ""
    readonly property bool veryStale: ok && tier === "very_stale"
    readonly property bool dim: tier === "stale" || veryStale
    readonly property string locale: (Store.docs["i18n"] && Store.docs["i18n"].locale) || "en"
    readonly property var hours: d.hours || []
    readonly property var days: d.days || []
    readonly property var saved: d.places || []
    readonly property string unitTemp: I18n.tr("mod-weather.unit.temp." + (d.units || "metric"))
    readonly property string unitWind: I18n.tr("mod-weather.unit.wind." + (d.units || "metric"))
    readonly property real scaleLo: days.length ? Math.min.apply(null, days.map(function (x) { return x.min })) : 0
    readonly property real scaleHi: days.length ? Math.max.apply(null, days.map(function (x) { return x.max })) : 1
    // The chance of rain in the next three hours: the highest of them, when the daemon sent any.
    readonly property var rain3: {
        var m = null
        for (var i = 0; i < Math.min(3, hours.length); i++) {
            var v = hours[i].pop
            if (W.has(v) && (m === null || v > m)) m = v
        }
        return m
    }
    readonly property string ageText: {
        var a = W.ageParts(d.age_s)
        return a.n > 0 ? W.fill(I18n.tr(a.key), { n: a.n }) : I18n.tr(a.key)
    }
    readonly property string subText: {
        var parts = []
        if (d.updated_local) {
            parts.push(p.tier === "stale"
                ? I18n.tr("mod-weather.tier.stale") + " · " + p.ageText
                : W.fill(I18n.tr("mod-weather.updated"), { age: p.ageText }))
        }
        return parts.join(" · ")
    }
    readonly property string hiLo: days.length
        ? W.fill(I18n.tr("mod-weather.high_low"), { max: W.deg(days[0].max), min: W.deg(days[0].min) })
        : ""
    readonly property string sunText: {
        var s = d.sun
        if (!s) return ""
        if (s.polar === "day") return I18n.tr("mod-weather.sun.polar_day")
        if (s.polar === "night") return I18n.tr("mod-weather.sun.polar_night")
        var parts = []
        if (s.sunrise) parts.push(W.fill(I18n.tr("mod-weather.sun.rise"), { time: W.hm(s.sunrise) }))
        if (s.sunset) parts.push(W.fill(I18n.tr("mod-weather.sun.set"), { time: W.hm(s.sunset) }))
        return parts.join(" · ")
    }

    // Places mode state: the last search, the chosen result, and what the last action answered.
    property string mode: "weather"
    property int waitS: 0
    property var results: []
    property var selected: null
    property string searchStatus: ""
    property string saveStatus: ""

    Accessible.role: Accessible.Pane
    Accessible.name: I18n.tr("mod-weather.title")

    function css(c) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + c.a + ")"
    }

    // Short weekday of a local date, in the UI locale (Qt weekdays run Monday = 1 to Sunday = 7).
    function dayLabel(iso) {
        var t = W.ymd(iso)
        if (!t) return ""
        var dow = new Date(t[0], t[1] - 1, t[2]).getDay()
        return Qt.locale(p.locale).dayName(dow === 0 ? 7 : dow, Locale.ShortFormat)
    }

    // A place as the user reads it: "Tokyo, JP".
    function labelOf(pl) {
        return pl.name + (pl.country_code ? ", " + pl.country_code : "")
    }

    // A search result as the list and its accessible name read it: "Tokyo · Tokyo · Japan".
    function placeLine(pl) {
        return pl.name + (pl.admin ? " · " + pl.admin : "") + (pl.country ? " · " + pl.country : "")
    }

    function refresh() {
        Store.act("weather.refresh", {}, function (done, err) {
            if (done && done.data) p.waitS = done.data.started ? 0 : (done.data.retry_in_s || 0)
        })
    }

    function openSettings() {
        Store.act("settings.open", { key: "mods.weather.place" })
    }

    function runSearch() {
        var q = searchField.text.trim()
        p.selected = null
        p.saveStatus = ""
        if (q.length === 0) {
            p.results = []
            p.searchStatus = ""
            return
        }
        if (q.length < 2) {
            p.results = []
            p.searchStatus = I18n.tr("mod-weather.error.query_short")
            return
        }
        p.searchStatus = I18n.tr("mod-weather.search.searching")
        Store.act("weather.place.search", { query: q, lang: p.locale }, function (done, err) {
            if (q !== searchField.text.trim()) return
            if (err) {
                p.results = []
                p.searchStatus = I18n.tr(err.msg)
                return
            }
            p.results = (done && done.data && done.data.results) || []
            p.searchStatus = p.results.length === 0 ? W.fill(I18n.tr("mod-weather.search.none"), { query: q }) : ""
        })
    }

    // A search result is chosen for the preview; saving is a second, explicit step.
    function choose(place) {
        p.selected = place
        p.saveStatus = ""
    }

    function save() {
        if (!p.selected) return
        Store.act("weather.place.add", { place: p.selected }, function (done, err) {
            if (err) p.saveStatus = I18n.tr(err.msg)
            else p.saveStatus = I18n.tr(done && done.data && done.data.added === false
                ? "mod-weather.search.already" : "mod-weather.search.saved")
        })
    }

    function move(id, dir) {
        Store.act("weather.place.move", { id: id, dir: dir }, function (done, err) {
            if (err) p.saveStatus = I18n.tr(err.msg)
        })
    }

    function remove(id) {
        Store.act("weather.place.remove", { id: id }, function (done, err) {
            if (err) p.saveStatus = I18n.tr(err.msg)
        })
    }

    // The manual refresh's wait counts down on screen; the timer runs only while the panel is open and waiting.
    Timer {
        interval: 1000
        repeat: true
        running: p.live && p.waitS > 0
        onTriggered: p.waitS = Math.max(0, p.waitS - 1)
    }

    Connections {
        target: p
        function onHoursChanged() { trend.requestPaint() }
    }

    Column {
        id: body
        width: p.width
        spacing: Theme.gap

        // Header: the place and its age, then refresh, the places toggle and settings.
        Item {
            id: header
            width: body.width
            height: Math.max(titles.implicitHeight, buttons.height)
            Column {
                id: titles
                anchors.left: parent.left
                anchors.right: buttons.left
                anchors.rightMargin: Theme.gap
                anchors.top: parent.top
                spacing: 2
                Text {
                    width: parent.width
                    text: p.d.place ? p.d.place.name : I18n.tr("mod-weather.title")
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.pixelSize: Theme.fsTitle
                    font.family: Theme.fam(text, Theme.families)
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: p.subText
                    elide: Text.ElideRight
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                }
                Text {
                    width: parent.width
                    visible: p.waitS > 0
                    text: W.fill(I18n.tr("mod-weather.refresh_wait"), { n: p.waitS })
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                }
            }
            Row {
                id: buttons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.xs
                IconButton {
                    glyph: "↻"
                    a11y: I18n.tr("mod-weather.refresh")
                    onClicked: p.refresh()
                }
                Button {
                    label: p.mode === "places" ? I18n.tr("mod-weather.forecast") : I18n.tr("mod-weather.places")
                    onClicked: p.mode = p.mode === "places" ? "weather" : "places"
                }
                IconButton {
                    glyph: "⚙"
                    a11y: I18n.tr("mod-weather.settings")
                    onClicked: p.openSettings()
                }
            }
        }

        // The failure of the last fetch, beside the data it did not replace (offline, rate limit, server).
        Text {
            width: body.width
            wrapMode: Text.WordWrap
            visible: p.mode === "weather" && p.ok && p.d.reason !== undefined
            text: p.d.reason !== undefined
                ? I18n.tr(p.d.reason) + (p.d.next_try_s !== undefined
                    ? " · " + W.fill(I18n.tr("mod-weather.next_try"), { n: Math.max(1, Math.ceil(p.d.next_try_s / 60)) })
                    : "")
                : ""
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }

        // No forecast to show: the state in words (Shōjiki), with the call to action where there is one.
        Column {
            id: states
            width: body.width
            spacing: Theme.gap
            visible: p.mode === "weather" && !p.hasNow

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: !p.loaded ? I18n.tr("mod-weather.loading")
                    : p.noPlace ? I18n.tr("mod-weather.no_location")
                    : p.veryStale ? W.fill(I18n.tr("mod-weather.very_stale"), { time: W.hm(p.d.updated_local) })
                    : I18n.tr(p.d.reason || "mod-weather.loading")
                color: p.noPlace ? Theme.fg : Theme.dim
                font.pixelSize: p.noPlace ? Theme.fsTitle : Theme.fs
                font.family: Theme.fam(text, Theme.families)
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: p.noPlace
                text: I18n.tr("mod-weather.no_location.help")
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: p.veryStale && p.d.reason !== undefined
                text: p.d.reason !== undefined ? I18n.tr(p.d.reason) : ""
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
            }
            Text {
                width: parent.width
                visible: p.d.next_try_s !== undefined && !p.noPlace
                text: p.d.next_try_s !== undefined
                    ? W.fill(I18n.tr("mod-weather.next_try"), { n: Math.max(1, Math.ceil(p.d.next_try_s / 60)) })
                    : ""
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
            }
            Button {
                visible: p.noPlace
                label: I18n.tr("mod-weather.search.label")
                primary: true
                onClicked: p.mode = "places"
            }
        }

        // Hero: glyph, temperature, feels and the day's high and low. Stale values are dimmed (and the header says so).
        Row {
            id: hero
            width: body.width
            spacing: Theme.pad
            visible: p.mode === "weather" && p.hasNow
            opacity: p.dim ? Theme.staleOpacity : 1
            Text {
                text: p.hasNow ? W.glyph(p.now.code, p.now.is_day) : ""
                color: Theme.fg
                font.pixelSize: 44
                font.family: Theme.fam(text, Theme.families)
            }
            Column {
                spacing: 2
                Text {
                    text: p.hasNow ? W.num(p.now.temp) + p.unitTemp : ""
                    color: Theme.fg
                    font.pixelSize: 40
                    font.family: Theme.fam(text, Theme.families)
                }
                Text {
                    text: p.hasNow ? I18n.tr("mod-weather.condition." + p.now.code) : ""
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                }
                Text {
                    text: p.hasNow ? W.fill(I18n.tr("mod-weather.feels"), { temp: W.num(p.now.feels) + p.unitTemp }) : ""
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                }
                Text {
                    visible: p.hiLo !== ""
                    text: p.hiLo
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                }
            }
        }

        // Chips: only the values the daemon sent (an empty chip is no chip).
        Flow {
            width: body.width
            spacing: Theme.gap
            visible: p.mode === "weather" && p.hasNow
            Chip {
                visible: p.rain3 !== null
                text: p.rain3 !== null ? W.fill(I18n.tr("mod-weather.chip.rain_3h"), { pop: W.num(p.rain3) }) : ""
            }
            Chip {
                visible: W.has(p.now.wind)
                text: W.has(p.now.wind)
                    ? W.fill(I18n.tr("mod-weather.chip.wind"), { speed: W.num(p.now.wind), unit: p.unitWind })
                        + (W.has(p.now.gust) ? " · " + W.fill(I18n.tr("mod-weather.chip.gust"), { gust: W.num(p.now.gust), unit: p.unitWind }) : "")
                    : ""
            }
            Chip {
                visible: W.has(p.now.humidity)
                text: W.has(p.now.humidity) ? W.fill(I18n.tr("mod-weather.chip.humidity"), { pct: W.num(p.now.humidity) }) : ""
            }
            Chip {
                visible: W.has(p.now.uv)
                text: W.has(p.now.uv)
                    ? W.fill(I18n.tr("mod-weather.chip.uv"), {
                        index: W.num(p.now.uv),
                        level: I18n.tr("mod-weather.uv." + W.uvLevel(p.now.uv))
                    })
                    : ""
            }
        }

        // Hourly strip: the temperature as a line, the chance of rain as bars, one column per hour, starting now.
        Flickable {
            id: strip
            width: body.width
            height: 100
            visible: p.mode === "weather" && p.ok && p.hours.length > 0 && !p.veryStale
            clip: true
            activeFocusOnTab: true
            flickableDirection: Flickable.HorizontalFlick
            contentWidth: hourRow.width
            contentHeight: height
            boundsBehavior: Flickable.StopAtBounds
            Accessible.role: Accessible.List
            Accessible.name: I18n.tr("mod-weather.hours")
            Keys.onLeftPressed: contentX = Math.max(0, contentX - 52)
            Keys.onRightPressed: contentX = Math.min(Math.max(0, contentWidth - width), contentX + 52)
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: function (event) {
                    var step = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                    strip.contentX = Math.max(0, Math.min(Math.max(0, strip.contentWidth - strip.width), strip.contentX - step / 2))
                }
            }
            Item {
                id: hourRow
                width: p.hours.length * 52
                height: strip.height
                Canvas {
                    id: trend
                    width: hourRow.width
                    height: 100
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var n = p.hours.length
                        if (n < 2) return
                        var lo = Infinity
                        var hi = -Infinity
                        for (var i = 0; i < n; i++) {
                            var t = p.hours[i].temp
                            if (t < lo) lo = t
                            if (t > hi) hi = t
                        }
                        var span = Math.max(1, hi - lo)
                        ctx.strokeStyle = p.css(Theme.fg)
                        ctx.lineWidth = 1.5
                        ctx.beginPath()
                        for (var j = 0; j < n; j++) {
                            // The line lives in its own band (y 30 to 42), between the glyph and the value.
                            var x = j * 52 + 26
                            var y = 42 - (p.hours[j].temp - lo) / span * 12
                            if (j === 0) ctx.moveTo(x, y)
                            else ctx.lineTo(x, y)
                        }
                        ctx.stroke()
                    }
                }
                Repeater {
                    model: p.hours
                    Item {
                        x: index * 52
                        width: 52
                        height: strip.height
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 0
                            text: index === 0 ? I18n.tr("mod-weather.now") : W.hm(modelData.t)
                            color: index === 0 ? Theme.fg : Theme.dim
                            font.pixelSize: Theme.fsCaption
                            font.family: Theme.fam(text, Theme.families)
                        }
                        // Rows: time 0, glyph 12, temperature line 30–42, value 46, chance of rain 62,
                        // rain bar from the bottom (at most 22 px tall).
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 12
                            text: W.glyph(modelData.code, modelData.is_day)
                            color: Theme.fg
                            font.pixelSize: Theme.fs
                            font.family: Theme.fam(text, Theme.families)
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 46
                            text: W.deg(modelData.temp)
                            color: Theme.fg
                            font.pixelSize: Theme.fsCaption
                            font.family: Theme.fam(text, Theme.families)
                        }
                        Text {
                            visible: W.has(modelData.pop) && modelData.pop >= 30
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 62
                            text: visible ? W.num(modelData.pop) + "%" : ""
                            color: Theme.dim
                            font.pixelSize: Theme.fsCaption
                            font.family: Theme.fam(text, Theme.families)
                        }
                        Rectangle {
                            visible: W.has(modelData.pop)
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: 12
                            height: W.has(modelData.pop) ? Math.max(2, modelData.pop / 100 * 22) : 0
                            radius: 2
                            color: Theme.accent
                            opacity: W.has(modelData.pop) ? 0.35 + 0.65 * modelData.pop / 100 : 0
                        }
                    }
                }
            }
            FocusRing { anchors.fill: parent; shown: strip.activeFocus; corner: Theme.rSm }
        }

        // Seven days on one shared scale: each bar spans the day's low to its high.
        Text {
            width: body.width
            visible: p.mode === "weather" && p.ok && p.days.length > 0 && !p.veryStale
            text: I18n.tr("mod-weather.days")
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }
        Column {
            width: body.width
            spacing: 4
            visible: p.mode === "weather" && p.ok && p.days.length > 0 && !p.veryStale
            Repeater {
                model: p.days
                Row {
                    width: body.width
                    height: 20
                    spacing: Theme.gap
                    Text {
                        width: 36
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: index === 0 ? I18n.tr("mod-weather.today") : p.dayLabel(modelData.date)
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                    }
                    Text {
                        width: 22
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: W.glyph(modelData.code, true)
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                    }
                    Text {
                        width: 34
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                        text: W.deg(modelData.min)
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                    }
                    Item {
                        width: body.width - 36 - 22 - 34 - 34 - Theme.gap * 4
                        height: parent.height
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 6
                            radius: 3
                            color: Theme.outline
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: (modelData.min - p.scaleLo) / Math.max(1, p.scaleHi - p.scaleLo) * parent.width
                            width: Math.max(6, (modelData.max - modelData.min) / Math.max(1, p.scaleHi - p.scaleLo) * parent.width)
                            height: 6
                            radius: 3
                            color: Theme.accent
                        }
                    }
                    Text {
                        width: 34
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: W.deg(modelData.max)
                        color: Theme.fg
                        font.pixelSize: Theme.fsCaption
                    }
                }
            }
        }

        Text {
            width: body.width
            visible: p.mode === "weather" && p.ok && p.sunText !== ""
            wrapMode: Text.WordWrap
            text: p.sunText
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }

        // Places mode: search, preview, save; then the saved list. The top place is the default unless Settings
        // names another; the move buttons change the order and remove drops a place.
        Column {
            id: places
            width: body.width
            spacing: Theme.gap
            visible: p.mode === "places"

            Text {
                width: parent.width
                text: I18n.tr("mod-weather.search.label")
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
            }
            Rectangle {
                width: parent.width
                height: Theme.controlH
                radius: Theme.rSm
                color: Theme.containerHigh
                border.width: 1
                border.color: searchField.activeFocus ? Theme.focusRing : Theme.outline
                TextInput {
                    id: searchField
                    anchors.fill: parent
                    anchors.margins: Theme.gap
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    Accessible.role: Accessible.EditableText
                    Accessible.name: I18n.tr("mod-weather.search.label")
                    onTextChanged: debounce.restart()
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: searchField.text === ""
                        text: I18n.tr("mod-weather.search.placeholder")
                        color: Theme.dim
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                    }
                }
            }
            Timer {
                id: debounce
                interval: 300
                onTriggered: p.runSearch()
            }
            Text {
                width: parent.width
                visible: p.searchStatus !== ""
                wrapMode: Text.WordWrap
                text: p.searchStatus
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
            }
            Column {
                width: parent.width
                spacing: 2
                Repeater {
                    model: p.results
                    Rectangle {
                        id: resultRow
                        width: places.width
                        height: 28
                        radius: Theme.rSm
                        activeFocusOnTab: true
                        color: p.selected && p.selected.id === modelData.id ? Theme.containerHigh : "transparent"
                        Keys.onReturnPressed: p.choose(modelData)
                        Keys.onEnterPressed: p.choose(modelData)
                        FocusRing { anchors.fill: parent; shown: resultRow.activeFocus; corner: Theme.rSm }
                        Text {
                            x: Theme.gap
                            width: parent.width - Theme.gap * 2
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: p.placeLine(modelData)
                            color: Theme.fg
                            font.pixelSize: Theme.fsCaption
                            font.family: Theme.fam(text, Theme.families)
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: p.choose(modelData)
                        }
                        Accessible.role: Accessible.ListItem
                        Accessible.name: p.placeLine(modelData)
                    }
                }
            }
            // The preview names the place as the list does, with its coordinates and zone, before it is saved.
            Text {
                width: parent.width
                visible: p.selected !== null
                wrapMode: Text.WordWrap
                color: Theme.fg
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: p.selected
                    ? W.fill(I18n.tr("mod-weather.search.preview"), {
                        name: p.labelOf(p.selected),
                        lat: Number(p.selected.lat).toFixed(2),
                        lon: Number(p.selected.lon).toFixed(2),
                        tz: p.selected.tz
                    })
                    : ""
            }
            Row {
                spacing: Theme.gap
                visible: p.selected !== null
                Button {
                    label: I18n.tr("mod-weather.search.save")
                    primary: true
                    onClicked: p.save()
                }
                Text {
                    visible: p.saveStatus !== ""
                    text: p.saveStatus
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                }
            }

            Text {
                width: parent.width
                text: I18n.tr("mod-weather.places")
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
            }
            Text {
                width: parent.width
                visible: p.saved.length === 0
                wrapMode: Text.WordWrap
                text: I18n.tr("mod-weather.saved.none")
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
            }
            Text {
                width: parent.width
                visible: p.saved.length > 1
                wrapMode: Text.WordWrap
                text: I18n.tr("mod-weather.saved.hint")
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
            }
            Repeater {
                model: p.saved
                Item {
                    id: savedRow
                    required property var modelData
                    required property int index
                    width: places.width
                    height: 28
                    readonly property bool isDefault: modelData.id === p.d.default_id
                    Row {
                        id: rowButtons
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        IconButton {
                            glyph: "↑"
                            enabled: savedRow.index > 0
                            a11y: W.fill(I18n.tr("mod-weather.saved.up"), { name: savedRow.modelData.name })
                            onClicked: p.move(savedRow.modelData.id, "up")
                        }
                        IconButton {
                            glyph: "↓"
                            enabled: savedRow.index < p.saved.length - 1
                            a11y: W.fill(I18n.tr("mod-weather.saved.down"), { name: savedRow.modelData.name })
                            onClicked: p.move(savedRow.modelData.id, "down")
                        }
                        IconButton {
                            glyph: "✕"
                            a11y: W.fill(I18n.tr("mod-weather.saved.remove"), { name: savedRow.modelData.name })
                            onClicked: p.remove(savedRow.modelData.id)
                        }
                    }
                    Chip {
                        id: defaultChip
                        anchors.right: rowButtons.left
                        anchors.rightMargin: Theme.gap
                        anchors.verticalCenter: parent.verticalCenter
                        visible: savedRow.isDefault
                        text: I18n.tr("mod-weather.saved.default")
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.right: savedRow.isDefault ? defaultChip.left : rowButtons.left
                        anchors.rightMargin: Theme.gap
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: p.labelOf(savedRow.modelData)
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                    }
                }
            }
        }

        // Footer: the refresh cadence, then the credit the CC BY 4.0 licence asks for.
        Text {
            width: body.width
            wrapMode: Text.WordWrap
            text: (d.refresh_min ? W.fill(I18n.tr("mod-weather.refresh_every"), { n: d.refresh_min }) + " · " : "")
                + I18n.tr("mod-weather.credit")
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }
    }
}
