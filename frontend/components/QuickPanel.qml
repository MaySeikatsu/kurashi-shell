import QtQuick
import "../core"
import "quick"

// Quick settings (K24): the `quick` panel of runtime.ui, opened by the bar's quick button
// (`quick.toggle`). Sections in order: Wi-Fi (network), Power, Audio output, Bluetooth (K24, W12). Each
// section shows its controls while its service is available, else one dim line saying why. The Stage makes
// this only while its card is up, so each section watches its own document only then (Ma).
Column {
    id: quick
    width: parent.width
    spacing: Theme.pad

    Text {
        width: quick.width
        color: Theme.fg
        font.pixelSize: Theme.fsTitle
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.heading")
    }
    // K28: mod tiles (caffeine, wallpaper next, VPN) wrap above the sections; none takes no space.
    SlotHost { slot: "quick.tiles"; layout: "flow"; width: quick.width }
    NetworkSection {}
    PowerSection {}
    AudioSection {}
    BluetoothSection {}
}
