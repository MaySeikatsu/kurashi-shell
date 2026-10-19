import QtQuick
import qs.core
import qs.components.quick

// The wallpaper tile in quick settings (K28 slot `quick.tiles`, W18): a QuickTile, so it has the core tiles' size and look.
// Its subtitle is the picture on the output (by name); its main zone moves every output to the next picture
// (`wallpaper.next`); its arrow, or Right, opens the picker panel. The slot shows it only while the daemon says the mod is
// available; the tile subscribes to `mod.wallpaper` for its own line, and that subscription is all it does.
QuickTile {
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n

    Watch { doc: "mod.wallpaper" }
    readonly property var doc: Store.docs["mod.wallpaper"] || ({})
    readonly property bool up: doc.available === true && (doc.backend || ({})).available === true
    // The picture of the first output (by name) that has one; "" while none is applied.
    readonly property string picture: {
        var outs = doc.outputs || ({})
        var names = Object.keys(outs).sort()
        for (var i = 0; i < names.length; i++) {
            var path = String((outs[names[i]] || ({})).path || "")
            if (path !== "") return path.split("/").pop().replace(/\.[^.]*$/, "")
        }
        return ""
    }

    glyph: "▣"
    label: I18n.tr("mod-wallpaper.tile.title")
    subtitle: picture !== "" ? picture : I18n.tr("mod-wallpaper.tile.next")
    // Unavailable: why, as the backend says it (the tile dims). Nothing is said before the document arrives.
    reason: doc.available === undefined || up ? "" : I18n.tr((doc.backend || ({})).reason || "mod-wallpaper.backend.down")
    toggles: false
    acts: true
    hasPage: true
    onActivated: Store.act("wallpaper.next", {}, function () {})
    onPageRequested: Store.act("mod.panel.open", {id: "wallpaper", panel: "wallpaper"}, function () {})
}
