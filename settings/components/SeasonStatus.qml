import QtQuick
import "../core"

// Under the seasonal tint (旬, I281): what it does today — the solar term, the season its colours lean toward and how
// far (`theme.appearance.season`, the daemon's numbers). Nothing shows while the tint is off.
Text {
    id: st
    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
    antialiasing: !Theme.pixelType
    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
    readonly property var s: (Store.theme && Store.theme.appearance && Store.theme.appearance.season) || ({})
    readonly property bool on: s.term !== undefined
    objectName: "season-status"
    visible: on
    height: visible ? Math.max(implicitHeight, Theme.controlH) : 0
    width: parent ? parent.width : 400
    verticalAlignment: Text.AlignVCenter
    wrapMode: Text.WordWrap
    color: Theme.dim
    font.pixelSize: Theme.fs - 1
    font.family: Theme.fam(text, Theme.families)
    text: !on ? "" : I18n.fmt("theme.season.detail", {
        term: s.term, romaji: s.romaji, strength: s.strength,
        season: I18n.tr("theme.season.toward." + s.season)
    })
}
