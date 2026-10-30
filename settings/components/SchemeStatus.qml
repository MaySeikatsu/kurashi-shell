import QtQuick
import "../core"

// Under light or dark (K55): why the scheme in effect is what it is — the system's preference (`auto`), the wallpaper's
// brightness (`wallpaper`), or that neither answers yet, then dark (`theme.appearance.scheme_detail`, the daemon's
// words) — and, while a style holds it, "Back to Auto": the mode you had before the style (`scheme_before`), one undo
// step (`theme.scheme.restore`). Nothing shows for a plain dark or light.
Flow {
    id: ss
    readonly property var ap: (Store.theme && Store.theme.appearance) || ({})
    readonly property string detail: ss.ap.scheme_detail || ""
    readonly property string before: ss.ap.scheme_before || ""
    readonly property string effective: ss.ap.scheme_effective || ""
    // The test hook: the line as shown, "" when hidden.
    readonly property string text: ss.visible ? (ss.detail !== "" ? line.text : "") + (ss.before !== "" ? " | " + back.label : "") : ""

    visible: ss.detail !== "" || ss.before !== ""
    height: visible ? implicitHeight : 0
    width: parent ? parent.width : 400
    spacing: Theme.gap
    objectName: "scheme-status"

    Text {
        id: line
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        visible: ss.detail !== ""
        width: Math.min(implicitWidth, ss.width)
        height: Math.max(implicitHeight, Theme.controlH)
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fs - 1
        font.family: Theme.fam(text, Theme.families)
        text: ss.detail === "" ? ""
            : I18n.fmt("theme.scheme.detail." + ss.detail, { scheme: I18n.tr("theme.scheme." + (ss.effective || "dark")) })
    }
    Button {
        id: back
        objectName: "scheme-back"
        visible: ss.before !== ""
        label: I18n.fmt("theme.scheme.back", { mode: I18n.tr("config.choice.scheme." + ss.before) })
        enabled: Store.live
        onClicked: Store.act("theme.scheme.restore", {})
    }
}
