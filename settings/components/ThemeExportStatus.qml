import QtQuick
import Quickshell
import "../core"

// Under the `theme.export` row (K49, W34): what became of each chosen app, from `svc.theme_export` — where its file went,
// the lines its own config needs (the include line, and the lines of qt6ct and kdeglobals) with a Copy key for each
// (wl-copy through the launcher's `calc:<text>` launch, K44), and for gsettings the values written and the ones already in
// effect. kurashid never edits an app's own config, so a line that is not there yet is the user's one step (DMS
// `IncludeSetupBanner` writes the include itself; we only show it). A stale include (the file of an earlier version) says
// so. Errors are their i18n keys. The document is watched only while this shows (Ma).
Column {
    id: ex
    spacing: Theme.gap

    readonly property bool active: visible
    property bool held: false
    function hold(on) {
        if (on === held) return
        held = on
        if (on) Store.watch("svc.theme_export")
        else Store.unwatch("svc.theme_export")
    }
    onActiveChanged: hold(active)
    Component.onCompleted: hold(active)
    Component.onDestruction: hold(false)

    readonly property var chosen: { var v = Store.valueOf("theme.export"); return Array.isArray(v) ? v : [] }
    readonly property var doc: Store.docs["svc.theme_export"]
    readonly property var targets: ex.doc && Array.isArray(ex.doc.targets) ? ex.doc.targets : []
    // Copies by row (an app's include is keyed by the app's name, its lines by `name#index`): the line copied, or {error}.
    property var copied: ({})
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string xdg: Quickshell.env("XDG_CONFIG_HOME") || ""
    // Under $HOME a path reads `~/…`. Under $XDG_CONFIG_HOME (when that lies outside $HOME) it reads `$XDG_CONFIG_HOME/…`:
    // a `~` there would name the wrong folder (W36).
    function tilde(p) {
        var s = String(p)
        if (ex.home !== "" && s.indexOf(ex.home + "/") === 0) return "~" + s.substring(ex.home.length)
        if (ex.xdg !== "" && s.indexOf(ex.xdg + "/") === 0) return "$XDG_CONFIG_HOME" + s.substring(ex.xdg.length)
        return s
    }
    function appName(n) { return I18n.has("config.choice.export." + n) ? I18n.tr("config.choice.export." + n) : n }
    function setList(v) { return Array.isArray(v) ? v.join(", ") : "" }
    // The rows of an app: its include (when it has one), then its lines.
    function rowsOf(t) {
        var out = []
        if (t.include) out.push({ key: t.name, include: true, file: t.include.file, section: "", line: t.include.line,
                                  present: t.include.present === true, stale: t.include.stale === true })
        var lines = Array.isArray(t.lines) ? t.lines : []
        for (var i = 0; i < lines.length; i++)
            out.push({ key: t.name + "#" + i, include: false, file: lines[i].file, section: lines[i].section || "",
                       line: lines[i].line, present: lines[i].present === true, stale: false })
        return out
    }
    function copy(key, line) {
        Store.act("launcher.launch", { id: "calc:" + line }, function (m) {
            var c = Object.assign({}, ex.copied)
            c[key] = m.t === "done" ? { line: line } : { error: Store.actError(m, "settings.export.copy_failed") }
            ex.copied = c
        })
    }

    // Chosen apps, but no answer yet (the first export runs after the theme).
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: ex.chosen.length > 0 && ex.doc === undefined
        color: Theme.dim
        font.pixelSize: Theme.fs - 2
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("settings.export.waiting")
    }

    Repeater {
        model: ex.targets
        delegate: Column {
            id: t
            required property var modelData
            readonly property bool settingsOnly: modelData.name === "gsettings"
            width: ex.width
            spacing: 2
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                width: parent.width
                elide: Text.ElideMiddle
                color: Theme.fg
                font.pixelSize: Theme.fs - 1
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                text: ex.appName(t.modelData.name)
            }
            // The desktop settings: what they are, what was set, what was in effect already.
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                visible: t.settingsOnly
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("theme.export.settings_help")
            }
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                visible: t.settingsOnly && Array.isArray(t.modelData.set) && t.modelData.set.length > 0
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.fg
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: I18n.fmt("theme.export.settings_set", { keys: ex.setList(t.modelData.set) })
            }
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                visible: t.settingsOnly && Array.isArray(t.modelData.same) && t.modelData.same.length > 0
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: I18n.fmt("theme.export.settings_same", { keys: ex.setList(t.modelData.same) })
            }
            // Files: where the file went, or that it is up to date.
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                visible: !t.settingsOnly && !t.modelData.error && !!t.modelData.path
                width: parent.width
                elide: Text.ElideMiddle
                color: Theme.dim
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: I18n.fmt(t.modelData.written === false ? "settings.export.same" : "settings.export.file",
                               { path: ex.tilde(t.modelData.path || "") })
            }
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                visible: !!t.modelData.error
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.error
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: "✕ " + I18n.fmt("settings.export.error", { reason: I18n.tr(t.modelData.error || "") })
            }
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                visible: Array.isArray(t.modelData.unknown) && t.modelData.unknown.length > 0
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: "⊘ " + I18n.fmt("settings.export.unknown", { names: (t.modelData.unknown || []).join(", ") })
            }
            // The include and the lines: present ones say so; the others show the line, the file it goes in and Copy.
            Repeater {
                model: ex.rowsOf(t.modelData)
                delegate: Column {
                    id: row
                    required property var modelData
                    readonly property var cp: ex.copied[modelData.key] || null
                    width: t.width
                    spacing: 2
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        visible: row.modelData.present === true
                        width: parent.width
                        elide: Text.ElideMiddle
                        color: Theme.dim
                        font.pixelSize: Theme.fs - 2
                        font.family: Theme.fam(text, Theme.families)
                        text: row.modelData.include
                              ? "✓ " + I18n.fmt("settings.export.included", { file: ex.tilde(row.modelData.file) })
                              : I18n.fmt("theme.export.line_present", { file: ex.tilde(row.modelData.file) })
                    }
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        visible: row.modelData.present !== true
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.fg
                        font.pixelSize: Theme.fs - 2
                        font.family: Theme.fam(text, Theme.families)
                        text: row.modelData.include
                              ? "↳ " + I18n.fmt("settings.export.add_line", { app: ex.appName(t.modelData.name), file: ex.tilde(row.modelData.file) })
                              : I18n.fmt(row.modelData.section !== "" ? "theme.export.line_add_section" : "theme.export.line_add",
                                         { file: ex.tilde(row.modelData.file), section: row.modelData.section })
                    }
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        visible: row.modelData.stale === true
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.error
                        font.pixelSize: Theme.fs - 2
                        font.family: Theme.fam(text, Theme.families)
                        text: "✕ " + I18n.tr("theme.export.stale")
                    }
                    Row {
                        visible: row.modelData.present !== true
                        width: parent.width
                        spacing: Theme.gap
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - copyKey.width - parent.spacing
                            height: lineText.implicitHeight + Theme.gap
                            radius: Theme.rSm
                            color: Theme.surface
                            border.width: 1
                            border.color: Theme.containerHigh
                            Text {
                                id: lineText
                                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                                anchors.verticalCenter: parent.verticalCenter
                                x: Theme.gap
                                width: parent.width - 2 * Theme.gap
                                elide: Text.ElideRight
                                color: Theme.fg
                                font.pixelSize: Theme.fs - 1
                                font.family: "monospace"
                                text: row.modelData.line
                            }
                        }
                        Button {
                            id: copyKey
                            objectName: row.modelData.include ? "copy:" + t.modelData.name : "copy:" + row.modelData.key
                            anchors.verticalCenter: parent.verticalCenter
                            label: row.cp && row.cp.line === row.modelData.line ? I18n.tr("settings.export.copied") : I18n.tr("settings.export.copy")
                            enabled: Store.live
                            onClicked: ex.copy(row.modelData.key, row.modelData.line)
                        }
                    }
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        visible: !!row.cp && !!row.cp.error
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.error
                        font.pixelSize: Theme.fs - 2
                        font.family: Theme.fam(text, Theme.families)
                        text: row.cp && row.cp.error ? "✕ " + row.cp.error : ""
                    }
                }
            }
        }
    }
}
