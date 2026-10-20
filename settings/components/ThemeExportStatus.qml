import QtQuick
import Quickshell
import "../core"

// Under the `theme.export` row (K49): what became of each chosen app, from `svc.theme_export` — where its file went, and,
// while the app does not read that file yet (`include.present` false), the line to add, the config file it goes in and a
// Copy key (wl-copy through the launcher's `calc:<text>` launch, K44). kurashid never edits an app's own config, so this
// is the user's one step (DMS `IncludeSetupBanner`, which writes the include itself; we only show it). Errors are their
// i18n keys. The document is watched only while this shows (Ma).
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
    // Copies by app: the line copied, or {error}.
    property var copied: ({})
    readonly property string home: Quickshell.env("HOME") || ""
    function tilde(p) { return ex.home !== "" && String(p).indexOf(ex.home + "/") === 0 ? "~" + String(p).substring(ex.home.length) : String(p) }
    function appName(n) { return I18n.has("config.choice.export." + n) ? I18n.tr("config.choice.export." + n) : n }
    function copy(name, line) {
        Store.act("launcher.launch", { id: "calc:" + line }, function (m) {
            var c = Object.assign({}, ex.copied)
            c[name] = m.t === "done" ? { line: line } : { error: Store.actError(m, "settings.export.copy_failed") }
            ex.copied = c
        })
    }

    // Chosen apps, but no answer yet (the first export runs after the theme).
    Text {
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
            readonly property var inc: modelData.include || null
            readonly property var cp: ex.copied[modelData.name] || null
            width: ex.width
            spacing: 2
            Text {
                width: parent.width
                elide: Text.ElideMiddle
                color: Theme.fg
                font.pixelSize: Theme.fs - 1
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                text: ex.appName(t.modelData.name)
            }
            Text {
                visible: !t.modelData.error && !!t.modelData.path
                width: parent.width
                elide: Text.ElideMiddle
                color: Theme.dim
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: I18n.fmt(t.modelData.written === false ? "settings.export.same" : "settings.export.file",
                               { path: ex.tilde(t.modelData.path || "") })
            }
            Text {
                visible: !!t.modelData.error
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.error
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: "✕ " + I18n.fmt("settings.export.error", { reason: I18n.tr(t.modelData.error || "") })
            }
            Text {
                visible: Array.isArray(t.modelData.unknown) && t.modelData.unknown.length > 0
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: "⊘ " + I18n.fmt("settings.export.unknown", { names: (t.modelData.unknown || []).join(", ") })
            }
            Text {
                visible: !!t.inc && t.inc.present === true
                width: parent.width
                elide: Text.ElideMiddle
                color: Theme.dim
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: "✓ " + I18n.fmt("settings.export.included", { file: ex.tilde(t.inc ? t.inc.file : "") })
            }
            // Not read yet: the line, the file it goes in, Copy.
            Text {
                visible: !!t.inc && t.inc.present === false
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.fg
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: "↳ " + I18n.fmt("settings.export.add_line", { app: ex.appName(t.modelData.name), file: ex.tilde(t.inc ? t.inc.file : "") })
            }
            Row {
                visible: !!t.inc && t.inc.present === false
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
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.gap
                        width: parent.width - 2 * Theme.gap
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.pixelSize: Theme.fs - 1
                        font.family: "monospace"
                        text: t.inc ? t.inc.line : ""
                    }
                }
                Button {
                    id: copyKey
                    objectName: "copy:" + t.modelData.name
                    anchors.verticalCenter: parent.verticalCenter
                    label: t.cp && t.cp.line === (t.inc ? t.inc.line : "") ? I18n.tr("settings.export.copied") : I18n.tr("settings.export.copy")
                    enabled: Store.live
                    onClicked: ex.copy(t.modelData.name, t.inc.line)
                }
            }
            Text {
                visible: !!t.cp && !!t.cp.error
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.error
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: t.cp && t.cp.error ? "✕ " + t.cp.error : ""
            }
        }
    }
}
