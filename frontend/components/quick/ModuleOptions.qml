import QtQuick
import "../../core"
import "../expanded"
import ".."

// A control's options from the schema (W71, docs/ux/control-centre-modules.md): the settings the schema gives the module
// (`#[kurashi(module = "<id>")]`, what its right-click menu lists, I408), drawn in its card under the switch — a toggle as a
// switch row, a choice as a heading and its radio rows. A pure view of `schema.settings` and `config` (Shōjiki: the value in
// effect; a row the daemon holds is inert and says why, once). A choice writes the setting as one `apply`; a refusal shows
// under the rows. Advanced rows, lists and ranges stay in Settings (the page links it). Watches the schema only
// while the page is up (Ma).
Column {
    id: mo
    // The module ids whose rows show (a page shared by two controls lists both), and keys another part of the page draws.
    property var mids: []
    property var skip: []
    spacing: Theme.gap
    visible: rows.length > 0 || errText !== ""
    property string errText: ""
    Refusal { id: refusal }

    Watch { doc: "schema.settings"; active: mo.mids.length > 0 }
    Watch { doc: "config"; active: mo.mids.length > 0 }
    readonly property var schema: Store.docs["schema.settings"] || null
    readonly property var values: (Store.docs["config"] || {}).values || ({})
    readonly property var rows: {
        var out = [], s = schema
        if (!s || !s.pages) return out
        for (var i = 0; i < s.pages.length; i++)
            for (var j = 0; j < s.pages[i].sections.length; j++) {
                var rs = s.pages[i].sections[j].rows
                for (var k = 0; k < rs.length; k++) {
                    var r = rs[k], ms = r.modules || [], hit = false
                    for (var m = 0; m < mids.length; m++) if (ms.indexOf(mids[m]) >= 0) hit = true
                    if (hit && skip.indexOf(r.key) < 0 && r.advanced !== true
                        && (r.control === "toggle" || (r.control === "select" && !!r.choices))) out.push(r)
                }
            }
        // (the control's own settings first; how a click on its module behaves last)
        var own = out.filter(function (r) { return r.key.indexOf("quick.click.") !== 0 })
        return own.concat(out.filter(function (r) { return r.key.indexOf("quick.click.") === 0 }))
    }
    function entry(key) { return values[key] || null }
    function now(r) { var e = entry(r.key); return e && e.value !== undefined ? e.value : r.default }
    // Why a row does nothing now ("" when it can be used): a layer that holds it, or the daemon's reason.
    function why(r) {
        var e = entry(r.key)
        if (!e) return ""
        if (e.forced_by) return I18n.tr("island.quick.forced").replace("{by}", String(e.forced_by))
        // (a setting another one holds: the module menu's words, I408)
        if (e.reason === "settings.inert.requires") return I18n.tr("frontend.module.held")
        if (e.reason) return I18n.tr(String(e.reason))
        return ""
    }
    function set(key, v) {
        mo.errText = ""
        Store.apply([{ set: key, value: v }], function (errors) {
            if (errors && errors.length) mo.errText = refusal.text({ msg: String(errors[0].code || "") }, "quick.options.refused")
        })
    }

    Repeater {
        model: mo.rows
        delegate: Column {
            id: rowC
            required property var modelData
            readonly property var r: modelData
            readonly property string inert: mo.why(r)
            readonly property var value: mo.now(r)
            width: mo.width
            spacing: Theme.xs
            // A toggle: its label and its switch, as the page's own switch rows.
            Row {
                visible: rowC.r.control === "toggle"
                width: rowC.width
                spacing: Theme.gap
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    width: parent.width - sw.width - Theme.gap
                    anchors.verticalCenter: sw.verticalCenter
                    elide: Text.ElideRight
                    color: rowC.inert !== "" ? Theme.dim : Theme.fg
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr(rowC.r.label)
                }
                ToggleSwitch {
                    id: sw
                    // (a held switch draws off: its value is not in effect, Shōjiki — the line under it says why)
                    checked: rowC.value === true && rowC.inert === ""
                    enabled: rowC.inert === ""
                    label: I18n.tr(rowC.r.label)
                    onToggled: on => mo.set(rowC.r.key, on)
                }
            }
            // A choice: its label, then one radio row per choice (the one in effect marked).
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                visible: rowC.r.control === "select"
                width: rowC.width
                elide: Text.ElideRight
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr(rowC.r.label)
            }
            Repeater {
                model: rowC.r.control === "select" ? rowC.r.choices : []
                delegate: ChoiceRow {
                    required property var modelData
                    width: rowC.width
                    radio: true
                    title: I18n.tr(modelData.label)
                    checked: rowC.value === modelData.value
                    inert: rowC.inert !== "" || rowC.value === modelData.value
                    onActivated: mo.set(rowC.r.key, modelData.value)
                }
            }
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                visible: rowC.inert !== ""
                width: rowC.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: rowC.inert
            }
        }
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        visible: mo.errText !== ""
        width: mo.width
        wrapMode: Text.WordWrap
        color: Theme.error
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: mo.errText
    }
}
