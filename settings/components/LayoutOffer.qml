import QtQuick
import "../core"

// "Also use its layout" (W53.0b, K80, docs/ux/styles.md "Decided" 2 and 9): a style only dresses the shell; the layout
// that reads as its original — a taskbar with a start button, a menu bar and a dock — is its layout preset, a bundled
// profile the daemon marks `preset_of` the style (`config.profiles`). Under the style picker, while the style in effect
// has one, this offers it: the button shows what loading it would change (profile.preview, the Profiles page's review),
// and only "Use this layout" loads it (profile.load, one undo step). Never applied by itself (K45).
Column {
    id: lo
    readonly property string style: ((Store.theme && Store.theme.appearance) || {}).style || ""
    readonly property string preset: {
        var ps = (Store.config && Store.config.profiles) || []
        for (var i = 0; i < ps.length; i++) if (ps[i].preset_of === lo.style) return ps[i].name
        return ""
    }
    readonly property bool shown: style !== "" && style !== "none" && preset !== ""
    readonly property string styleName: { Store.schema; return Store.packLabel("styles", lo.style) }
    property var diff: null
    property var held: []
    property int kept: 0
    property bool reading: false
    property string message: ""
    // The test hook: the offer's line, "" when hidden.
    readonly property string text: shown ? line.text : ""

    visible: shown
    height: shown ? implicitHeight : 0
    width: parent ? parent.width : 400
    spacing: Theme.gap
    objectName: "layout-offer"
    onPresetChanged: { diff = null; message = "" }

    function review() {
        var name = lo.preset
        lo.reading = true
        lo.message = ""
        Store.act("profile.preview", { name: name }, function (m) {
            if (name !== lo.preset) return
            lo.reading = false
            if (m.t === "done") {
                var d = m.data || ({})
                lo.diff = d.diff || []
                lo.held = d.not_applied || []
                lo.kept = d.kept_user || 0
            } else {
                lo.message = Store.actError(m, "settings.err.profile_preview")
            }
        })
    }
    function load() {
        var name = lo.preset
        Store.act("profile.load", { name: name }, function (m) {
            if (m.t !== "done") { lo.message = Store.actError(m, "settings.err.profile_load"); return }
            lo.diff = null
            lo.message = I18n.fmt("settings.ui.profile_loaded_kept", { n: (m.data && m.data.kept_user) || 0 })
        })
    }

    Flow {
        width: lo.width
        spacing: Theme.gap
        Text {
            id: line
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            width: Math.min(implicitWidth, lo.width)
            height: Math.max(implicitHeight, Theme.controlH)
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.fmt("styles.layout.offer", { style: lo.styleName })
        }
        Button {
            objectName: "layout-offer-review"
            label: lo.diff === null ? I18n.tr("styles.layout.review") : I18n.tr("styles.layout.not_now")
            enabled: Store.live && !lo.reading
            onClicked: lo.diff === null ? lo.review() : (lo.diff = null)
        }
    }
    Column {
        visible: lo.diff !== null
        width: lo.width
        spacing: Theme.gap / 2
        ProfileReview {
            width: parent.width
            entries: lo.diff || []
            held: lo.held
            kept: lo.kept
        }
        Button {
            objectName: "layout-offer-load"
            primary: true
            label: I18n.tr("styles.layout.load")
            enabled: Store.live && lo.diff !== null && lo.diff.length > 0
            onClicked: lo.load()
        }
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        visible: lo.message !== ""
        width: lo.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fs - 2
        font.family: Theme.fam(text, Theme.families)
        text: lo.message
    }
}
