import QtQuick
import "../core"

// Under "Set the place by hand" (I601, K159): the place in effect and where it comes from — set by hand, or the mod
// that knows one — or that there is none, with what to do (`svc.location`, the daemon's words). Watched only while shown.
Label {
    id: ls
    readonly property var doc: Store.docs["svc.location"] || ({})
    readonly property string from: {
        var s = ls.doc.source || ""
        if (s.indexOf("mod:") !== 0) return I18n.tr("power.location.source.config")
        var id = s.slice(4)
        return I18n.has("mods." + id + ".name") ? I18n.tr("mods." + id + ".name") : id
    }
    objectName: "location-status"
    visible: ls.doc.available !== undefined
    height: visible ? Math.max(implicitHeight, Theme.controlH) : 0
    width: parent ? parent.width : 400
    verticalAlignment: Text.AlignVCenter
    wrapMode: Text.WordWrap
    dim: true
    font.pixelSize: Theme.fs - 1
    text: ls.doc.available === true
        ? I18n.fmt(ls.doc.name ? "power.location.in_effect" : "power.location.in_effect_unnamed", {
            name: ls.doc.name || "", lat: Number(ls.doc.lat).toFixed(2), lon: Number(ls.doc.lon).toFixed(2), from: ls.from })
        : I18n.tr(ls.doc.reason || "power.location.none")
    Component.onCompleted: Store.watch("svc.location")
    Component.onDestruction: Store.unwatch("svc.location")
}
