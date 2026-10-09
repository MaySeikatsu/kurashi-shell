import QtQuick
import qs.core
import qs.components
import qs.components.faces
import "Weather.js" as W

// Expanded view of the rain-soon face: the same fact with the place and the time it starts, and one
// action that opens the full panel (where the hourly strip and the seven days are).
FaceBase {
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n
    id: f
    // Loaded only while the expanded view shows it (ModLoader): current from its first frame (see Face.qml).
    current: true

    readonly property var d: Store.docs["mod.weather"] || ({})
    readonly property var rs: d.rain_soon || null
    Watch { doc: "mod.weather"; active: f.live }

    wantW: col.implicitWidth
    implicitHeight: col.implicitHeight

    Column {
        id: col
        anchors.centerIn: parent
        spacing: Theme.gap
        Text {
            visible: f.rs !== null
            text: f.rs
                ? "☂ " + W.fill(I18n.tr("mod-weather.rain_in"), { min: f.rs.in_min })
                    + " · " + I18n.tr("mod-weather.rain_intensity." + W.intensityKey(f.rs.intensity))
                : ""
            color: Theme.fg
            font.pixelSize: Theme.fsTitle
            font.family: Theme.fam(text, Theme.families)
        }
        Text {
            visible: f.rs !== null && f.d.place !== undefined
            text: f.rs && f.d.place
                ? W.fill(I18n.tr("mod-weather.rain_from"), { time: W.hm(f.rs.from) }) + " · " + f.d.place.name
                : ""
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }
        Button {
            label: I18n.tr("mod-weather.open_panel")
            primary: true
            onClicked: Store.act("mod.panel.open", { id: "weather", panel: "weather" })
        }
    }
}
