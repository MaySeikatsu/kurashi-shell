import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"

// Desktop widgets (K43; SekaiPop's desk): cards on the bottom layer, under the windows, on one side of each output —
// the time as four keys with the date and the day's progress, this month with today marked, what is playing (hidden
// while nothing plays) and today's weather (while the weather mod serves a place). Opt-in per output
// (`desktop.enabled`; the sekai decor recommends it). A pure view: every value comes from a document, every press is
// an action.
// Ma: no surface while off; the documents are watched only while the surface is shown; nothing animates on its own —
// the clock changes when svc.clock's minute patch arrives. Content-sized (K16): the window is the column of cards.
PanelWindow {
    id: desk
    required property var modelData
    screen: modelData

    BarConfig { id: bars; screen: desk.screen }
    readonly property bool on: bars.valueOf("desktop.enabled", false) === true
    readonly property bool onLeft: bars.valueOf("desktop.side", "right") === "left"
    function want(key) { return bars.valueOf("desktop." + key, true) === true }

    visible: on
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "kurashi-desktop"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    anchors { top: true; left: desk.onLeft; right: !desk.onLeft }
    margins {
        top: (bars.atTop ? Theme.barH : 0) + 28
        left: (bars.enabled && bars.edge === "left" ? Theme.barH : 0) + 32
        right: (bars.atRight ? Theme.barH : 0) + 32
    }
    implicitWidth: cards.width
    implicitHeight: Math.max(1, cards.height)

    Watch { doc: "svc.clock"; active: desk.visible }
    Watch { doc: "svc.media"; active: desk.visible && desk.want("media") }
    Watch { doc: "mod.weather"; active: desk.visible && desk.want("weather") && desk.weatherMod }
    Watch { doc: "mods"; active: desk.visible }
    readonly property var clock: Store.docs["svc.clock"] || ({})
    readonly property var media: Store.docs["svc.media"] || ({})
    readonly property var weather: Store.docs["mod.weather"] || ({})
    readonly property string locale: (Store.docs["i18n"] || {}).locale || "en"
    // On: an enabled native mod carries its `qml` map (PROTOCOL §5).
    readonly property bool weatherMod: {
        var m = (Store.docs["mods"] || {}).mods || []
        for (var i = 0; i < m.length; i++) if (m[i].id === "weather" && m[i].qml !== undefined) return true
        return false
    }

    readonly property int cardW: 300
    // A card: a Block with the panel's padding; keycap chrome outlines it and drops its hard shadow.
    component Card: Block {
        default property alias body: inner.data
        width: desk.cardW
        height: inner.childrenRect.height + 2 * Theme.pad + 2 * inset + Theme.shadowDy
        radius: Theme.rLg + 4
        fill: Theme.surfaceAlpha
        flatBorder: Theme.outline
        // Inside the Block's fill (its default property), which already sits within the outline and ring.
        Item {
            id: inner
            x: Theme.pad
            y: Theme.pad
            width: parent.width - 2 * Theme.pad
            height: childrenRect.height
        }
    }
    component Caption: Text {
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.weight: Theme.wBold
        font.letterSpacing: 1
        font.capitalization: Font.AllUppercase
        font.family: Theme.fam(text, Theme.families)
    }

    Column {
        id: cards
        width: desk.cardW
        spacing: Theme.pad + 4

        // ---- clock: four keys, the date, the day's progress ----
        Card {
            visible: desk.want("clock")
            Column {
                width: parent.width
                spacing: Theme.gap
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    Repeater {
                        model: [0, 1, -1, 2, 3]
                        delegate: Item {
                            id: keyItem
                            required property int modelData
                            readonly property string digits: (desk.clock.hh ?? "--") + (desk.clock.mm ?? "--")
                            width: modelData < 0 ? 14 : 54
                            height: 72 + Theme.shadowDy
                            Text {
                                visible: parent.modelData < 0
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -Theme.shadowDy / 2
                                color: Theme.accent
                                font.pixelSize: 40
                                font.weight: Font.Black
                                font.family: Theme.fam(text, Theme.families)
                                text: ":"
                            }
                            Block {
                                visible: keyItem.modelData >= 0
                                anchors.fill: parent
                                radius: Theme.rLg
                                ringScale: 0.67
                                fill: keyItem.modelData < 2 ? Theme.container : Theme.selected
                                Text {
                                    id: dig
                                    anchors.centerIn: parent
                                    color: Theme.fg
                                    font.pixelSize: 48
                                    font.weight: Font.Black
                                    font.family: Theme.fam(text, Theme.families)
                                    text: keyItem.digits.charAt(Math.max(0, keyItem.modelData))
                                    // A changed digit drops in from above (one spring per minute, on the patch).
                                    onTextChanged: if (desk.visible && Theme.springOn) drop.restart()
                                    NumberAnimation on anchors.verticalCenterOffset {
                                        id: drop
                                        running: false
                                        from: -14; to: 0
                                        duration: Theme.stdMs + 120
                                        easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot
                                    }
                                }
                            }
                        }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Theme.fg
                    font.pixelSize: Theme.fsTitle
                    font.weight: Theme.wBold
                    font.family: Theme.fam(text, Theme.families)
                    text: {
                        var d = desk.clock.date ? new Date(desk.clock.date + "T12:00:00") : null
                        return d ? d.toLocaleDateString(Qt.locale(desk.locale), "dddd, d MMMM") : ""
                    }
                }
                // The day's progress (SekaiPop's clock card): how much of today has gone, from the minute patch.
                Rectangle {
                    width: parent.width
                    height: Theme.keycap ? 12 : 6
                    radius: height / 2
                    color: Theme.keycap ? Theme.ring : Theme.containerHigh
                    border.width: Theme.keycap ? Theme.outlineW : 0
                    border.color: Theme.line
                    readonly property real day: ((parseInt(desk.clock.hh) || 0) * 60 + (parseInt(desk.clock.mm) || 0)) / 1440
                    Rectangle {
                        x: parent.border.width; y: parent.border.width
                        height: parent.height - 2 * y
                        width: Math.max(height, (parent.width - 2 * x) * parent.day)
                        radius: height / 2
                        color: Theme.accent
                    }
                }
            }
        }

        // ---- this month ----
        Card {
            visible: desk.want("calendar")
            Column {
                id: cal
                width: parent.width
                spacing: Theme.xs + 2
                readonly property date today: desk.clock.date ? new Date(desk.clock.date + "T12:00:00") : new Date()
                // The first column follows clock.week_start (auto: Sunday for Japanese, Monday otherwise), as the
                // island's calendar does.
                readonly property int first: {
                    var w = bars.valueOf("clock.week_start", "auto")
                    if (w === "sunday") return 0
                    if (w === "saturday") return 6
                    if (w === "monday") return 1
                    return desk.locale.indexOf("ja") === 0 ? 0 : 1
                }
                readonly property int lead: (new Date(today.getFullYear(), today.getMonth(), 1).getDay() - first + 7) % 7
                readonly property int days: new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate()
                Row {
                    width: parent.width
                    Caption {
                        width: parent.width - wk.width
                        text: cal.today.toLocaleDateString(Qt.locale(desk.locale), "MMMM yyyy")
                    }
                    Caption { id: wk; text: "" }
                }
                Grid {
                    columns: 7
                    spacing: 4
                    readonly property real cell: (cal.width - 6 * spacing) / 7
                    Repeater {
                        model: 7
                        delegate: Text {
                            required property int index
                            width: parent.cell
                            horizontalAlignment: Text.AlignHCenter
                            color: Theme.dim
                            font.pixelSize: Theme.fsCaption
                            font.weight: Theme.wBold
                            font.family: Theme.fam(text, Theme.families)
                            text: Qt.locale(desk.locale).dayName((cal.first + index) % 7, Locale.NarrowFormat)
                        }
                    }
                    Repeater {
                        model: cal.lead + cal.days
                        delegate: Item {
                            required property int index
                            readonly property int day: index - cal.lead + 1
                            readonly property bool isToday: day === cal.today.getDate()
                            width: parent.cell
                            height: 26 + (Theme.keycap ? 2 : 0)
                            Rectangle {
                                visible: parent.day > 0 && parent.isToday
                                anchors.centerIn: parent
                                width: 28; height: 24
                                radius: 12
                                color: Theme.accent
                                border.width: Theme.keycap ? Theme.outlineW : 0
                                border.color: Theme.line
                            }
                            Text {
                                visible: parent.day > 0
                                anchors.centerIn: parent
                                color: parent.isToday ? Theme.fgOnAccent : Theme.fg
                                font.pixelSize: Theme.fs
                                font.weight: parent.isToday ? Theme.wBold : Theme.wMedium
                                font.family: Theme.fam(text, Theme.families)
                                text: parent.day
                            }
                        }
                    }
                }
            }
        }

        // ---- now playing: shown while a player plays or is paused on a track ----
        Card {
            visible: desk.want("media") && desk.media.available === true && (desk.media.title || "") !== ""
            Row {
                width: parent.width
                spacing: Theme.pad
                Rectangle {
                    id: art
                    width: 72; height: 72
                    radius: Theme.rLg
                    color: Theme.selected
                    border.width: Theme.keycap ? Theme.outlineW : 0
                    border.color: Theme.line
                    clip: true
                    Image {
                        anchors.fill: parent
                        anchors.margins: parent.border.width
                        source: desk.visible ? (desk.media.art_url || "") : ""
                        sourceSize: Qt.size(144, 144)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status === Image.Ready
                    }
                    Icon {
                        anchors.centerIn: parent
                        name: "music_note"
                        glyph: "♪"
                        filled: true
                        size: 32
                        color: Theme.onSelected
                    }
                }
                Column {
                    width: parent.width - art.width - parent.spacing
                    spacing: 2
                    Caption { text: I18n.tr("frontend.desktop.now_playing") }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.pixelSize: Theme.fs + 1
                        font.weight: Theme.wBold
                        font.family: Theme.fam(text, Theme.families)
                        text: desk.media.title || ""
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        color: Theme.dim
                        font.pixelSize: Theme.fs - 1
                        font.family: Theme.fam(text, Theme.families)
                        text: desk.media.artist || ""
                    }
                    Row {
                        spacing: Theme.xs
                        readonly property var can: desk.media.can || ({})
                        IconButton {
                            icon: "skip_previous"; glyph: "⏮"
                            a11y: I18n.tr("action.media.prev")
                            enabled: parent.can.prev === true
                            onClicked: Store.act("media.prev")
                        }
                        IconButton {
                            icon: desk.media.playing ? "pause" : "play_arrow"; glyph: desk.media.playing ? "⏸" : "▶"
                            a11y: I18n.tr("action.media.play_pause")
                            lit: true
                            enabled: parent.can.play === true || parent.can.pause === true
                            onClicked: Store.act("media.play_pause")
                        }
                        IconButton {
                            icon: "skip_next"; glyph: "⏭"
                            a11y: I18n.tr("action.media.next")
                            enabled: parent.can.next === true
                            onClicked: Store.act("media.next")
                        }
                    }
                }
            }
        }

        // ---- weather: while the weather mod is on and serves today's values ----
        Card {
            id: wcard
            readonly property var now: desk.weather.now || ({})
            visible: desk.want("weather") && desk.weatherMod && desk.weather.available === true && desk.weather.now !== undefined
            Row {
                width: parent.width
                spacing: Theme.pad
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: desk.conditionIcon(wcard.now.code, wcard.now.is_day)
                    glyph: "☁"
                    filled: true
                    size: 52
                    color: Theme.secondary
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Caption { text: desk.weather.place ? desk.weather.place.name : "" }
                    Text {
                        color: Theme.fg
                        font.pixelSize: 34
                        font.weight: Font.Black
                        font.family: Theme.fam(text, Theme.families)
                        text: wcard.now.temp !== undefined ? Math.round(wcard.now.temp) + "°" : "—"
                    }
                    Text {
                        color: Theme.dim
                        font.pixelSize: Theme.fs - 1
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("mod-weather.condition." + (wcard.now.code || "unknown"))
                    }
                }
            }
        }
    }

    // The weather mod's condition codes as Material Symbols names.
    function conditionIcon(code, isDay) {
        switch (code) {
        case "clear": case "mainly_clear": return isDay === false ? "clear_night" : "sunny"
        case "partly_cloudy": return isDay === false ? "partly_cloudy_night" : "partly_cloudy_day"
        case "overcast": return "cloud"
        case "fog": return "foggy"
        case "drizzle": case "freezing_drizzle": case "rain": case "freezing_rain": case "showers": return "rainy"
        case "snow": case "snow_grains": case "snow_showers": return "weather_snowy"
        case "thunder": case "thunder_hail": return "thunderstorm"
        default: return "cloud"
        }
    }
}
