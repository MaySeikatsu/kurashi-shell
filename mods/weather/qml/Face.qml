import QtQuick
import qs.core
import qs.components.faces
import "Weather.js" as W

// Island face of the weather mod: rain soon (docs/ux/weather.md, "Beyond the basic job" 1). The daemon
// raises it once per onset and takes it back when the rain starts; this shows the daemon's fact: the
// minutes until the rain and its strength. No fact, no words (Shōjiki: nothing is invented).
FaceBase {
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n
    id: f
    // A mod's face is loaded only while it is the Island's face (ModLoader), so it is current from its first frame.
    // FaceBase draws nothing while `current` is false, and the Island's mod loader does not set it.
    current: true

    readonly property var d: Store.docs["mod.weather"] || ({})
    readonly property var rs: d.rain_soon || null
    Watch { doc: "mod.weather"; active: f.live }

    wantW: row.implicitWidth
    Accessible.role: Accessible.StaticText
    Accessible.name: rs ? W.fill(I18n.tr("mod-weather.rain_in"), { min: rs.in_min }) : ""

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.gap
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "☂"
            color: Theme.accent
            font.pixelSize: Theme.fs
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: f.rs !== null
            text: f.rs
                ? W.fill(I18n.tr("mod-weather.rain_in"), { min: f.rs.in_min })
                    + " · " + I18n.tr("mod-weather.rain_intensity." + W.intensityKey(f.rs.intensity))
                : ""
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
        }
    }
}
