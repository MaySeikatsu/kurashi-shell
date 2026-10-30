import QtQuick
import "../core"

// "Changed from the style" (W29, K53): while settings the style recreates differ from it — set by you or a profile
// (`theme.appearance.overrides`, the daemon's list) — one line names them, "3 settings differ from Washi: Chrome,
// Corners, Palette", with "Reset to Washi", which applies the style again (one undo step). Nothing shows with no style.
Flow {
    id: sd
    readonly property var ap: (Store.theme && Store.theme.appearance) || ({})
    readonly property string style: sd.ap.style || ""
    readonly property var keys: sd.ap.overrides || []
    readonly property bool shown: sd.style !== "" && sd.style !== "none" && sd.keys.length > 0
    readonly property string styleName: { Store.schema; return Store.packLabel("styles", sd.style) }
    readonly property string names: {
        var tr = I18n.strings
        var ls = sd.keys.slice(0, 4).map(function (k) { return I18n.tr(Store.labelOf(k)) })
        return ls.join(", ") + (sd.keys.length > 4 ? ", …" : "")
    }
    // The test hook: the line as shown, "" when hidden.
    readonly property string text: sd.shown ? line.text : ""

    visible: sd.shown
    height: sd.shown ? implicitHeight : 0
    width: parent ? parent.width : 400
    spacing: Theme.gap
    objectName: "differs"

    Text {
        id: line
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        width: Math.min(implicitWidth, sd.width)
        height: Math.max(implicitHeight, Theme.controlH)
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: sd.keys.length === 1
            ? I18n.fmt("settings.appearance.differs_one", { style: sd.styleName, keys: sd.names })
            : I18n.fmt("settings.appearance.differs_many", { n: sd.keys.length, style: sd.styleName, keys: sd.names })
    }
    Button {
        objectName: "differs-reset"
        label: I18n.fmt("settings.appearance.reset_to", { style: sd.styleName })
        enabled: Store.live
        onClicked: {
            var h = Store.rowOf("theme.style")
            if (h) Store.pickPack(h.row, sd.style)
        }
    }
}
