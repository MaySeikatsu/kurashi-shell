import QtQuick
import "../../core"

// Dark mode (the theme document's `appearance`, K53, K55): light or dark is the user's mode (every palette has both). The
// document says which scheme is in effect (a mode may follow the system or the wallpaper); a press writes the setting
// `theme.colors.scheme`, dark or light outright. W71: its page has the switch and the scheme's choices; Settings ›
// Appearance has the rest. W70: the logic QuickPanel held.
Control {
    id: c
    mid: "darkmode"
    page: "dark"
    settingsPage: "appearance"
    Watch { doc: "theme"; active: c.live }
    readonly property var ap: (Store.docs["theme"] || {}).appearance || ({})
    readonly property bool dark: String(ap.scheme_effective || ap.scheme || "") === "dark"
    known: Store.docs["theme"] !== undefined
    label: I18n.tr("island.quick.tile.dark")
    glyph: "☾"
    icon: "dark_mode"
    readonly property string glanceIcon: dark ? "dark_mode" : "light_mode"
    on: dark
    req: rqDark
    value: ap.scheme === "auto" || ap.scheme === "wallpaper"
        ? I18n.tr("island.quick.tile.dark." + ap.scheme) : I18n.tr(dark ? "island.quick.on" : "island.quick.off")
    Request {
        id: rqDark
        value: c.dark
        start: function (to, report) {
            Store.apply([{set: "theme.colors.scheme", value: to ? "dark" : "light"}], function (errors) {
                if (errors && errors.length) report(I18n.tr(String(errors[0].code || "power.quick.failed")))
            })
        }
    }
}
