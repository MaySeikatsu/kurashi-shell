import QtQuick
import qs.core
import qs.components
import "../Weather.js" as W

// Today's weather on the desk (`desk:weather`, W92 row 2; docs/ux/weather.md): the condition's icon, the place, the
// temperature and the condition in words. Height 0 while the mod has no place or no values yet (MODS.md, desk cards: a
// card with nothing to say is not drawn). The desk has no keyboard focus (K43): a click opens the weather panel.
Item {
    // Handed in by ModLoader (K26 loader contract).
    required property var store
    required property var theme
    required property var i18n
    id: dc

    // The card lives only while the desk is shown (its ModLoader is gated on that, Ma), so it watches for its lifetime:
    // the desk hides a card of height 0, and a watch gated on visibility would never see the snapshot that shows it.
    Watch { doc: "mod.weather" }

    readonly property var d: Store.docs["mod.weather"] || ({})
    readonly property var now: d.now || ({})
    readonly property bool wanted: d.available === true && d.now !== undefined

    width: parent ? parent.width : 300
    implicitHeight: wanted ? card.height : 0

    // The condition codes as Material Symbols names (the glyphs of Weather.js are the fallback without the icon font).
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

    DeskCard {
        id: card
        visible: dc.wanted
        width: dc.width

        Row {
            width: parent.width
            spacing: Theme.pad
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: dc.conditionIcon(dc.now.code, dc.now.is_day)
                glyph: W.glyph(dc.now.code, dc.now.is_day)
                filled: true
                size: 52
                color: Theme.secondary
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Label {
                    dim: true
                    font.pixelSize: Theme.fsCaption
                    font.weight: Theme.wBold
                    font.letterSpacing: 1
                    font.capitalization: Font.AllUppercase
                    text: dc.d.place ? dc.d.place.name : ""
                }
                Label {
                    font.pixelSize: 34
                    font.weight: Font.Black
                    text: W.deg(dc.now.temp)
                }
                Label {
                    dim: true
                    font.pixelSize: Theme.fs - 1
                    text: I18n.tr("mod-weather.condition." + (dc.now.code || "unknown"))
                }
            }
        }

        // Under nothing clickable: the whole card opens the panel.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Store.act("mod.panel.open", { id: "weather", panel: "weather" }, function () {})
        }
    }
}
