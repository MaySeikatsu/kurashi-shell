import QtQuick
import "../../core"
import ".."

// The display page (docs/ux/quick-settings.md, Design 2): the backlight's level (svc.brightness; the daemon serves one
// device, so there is one level, not one per output). Night light has its own tile and page since K47 (W23-system):
// this page points there.
Column {
    id: dp
    width: parent.width
    spacing: Theme.gap
    signal backRequested()

    function focusFirst() { header.forceActiveFocus() }

    readonly property var d: Store.docs["svc.brightness"] || ({})
    readonly property bool present: d.present === true

    PageHeader {
        id: header
        title: I18n.tr("island.quick.tile.display")
        backName: I18n.tr("island.quick.back")
        onBack: dp.backRequested()
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        width: dp.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.brightness.heading")
    }
    LevelRow {
        width: dp.width
        glyph: "☼"
        value: dp.present ? Math.max(0, Math.min(1, Number(dp.d.percent || 0) / 100)) : 0
        readout: dp.present ? Math.round(Number(dp.d.percent || 0)) + " %" : ""
        unavailable: !dp.present
        a11y: I18n.tr("island.brightness.heading")
        onMoved: v => Store.intent("brightness.set", v, "qs:quick")
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        visible: !dp.present
        width: dp.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("error.brightness.no_device")
    }
    Column {
        width: dp.width
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            width: parent.width
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("island.quick.display.night_light")
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("power.display.night_light_tile")
        }
    }
}
