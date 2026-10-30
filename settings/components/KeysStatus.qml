import QtQuick
import Quickshell
import "../core"

// Under "Shortcuts for the compositor" (K64, W38-keys): what became of the binds file, from `svc.keys` — where it went,
// whether the compositor's config includes it (the line with Copy, as the theme export's status: kurashid never edits
// the compositor's config), how many shortcuts are left out and why in short (each row says its own reason), Sway's
// reload (it reads the file on `swaymsg reload` only), and the cases where the file is not ours to write: a link another
// tool made (Home-Manager's, for niri), a file the user put there, a compositor without writing. The document is watched
// only while this shows (Ma).
Column {
    id: ks
    objectName: "keys-status"
    spacing: Theme.gap / 2

    property bool held: false
    function hold(on) {
        if (on === held) return
        held = on
        if (on) Store.watch("svc.keys")
        else Store.unwatch("svc.keys")
    }
    onVisibleChanged: hold(visible)
    Component.onCompleted: hold(visible)
    Component.onDestruction: hold(false)

    readonly property var doc: Store.docs["svc.keys"]
    readonly property string st: ks.doc && ks.doc.state ? ks.doc.state : ""
    readonly property bool on: Store.valueOf("keys.write") === true
    readonly property string home: Quickshell.env("HOME") || ""
    function tilde(p) { return ks.home !== "" && String(p).indexOf(ks.home + "/") === 0 ? "~" + String(p).substring(ks.home.length) : String(p) }
    readonly property int leftOut: {
        var b = ks.doc && Array.isArray(ks.doc.binds) ? ks.doc.binds : []
        return b.filter(function (x) { return x.state === "invalid" || x.state === "conflict" }).length
    }
    // The copy of the include line: "copied", "error: …" or "none" (the keys test reads it).
    property string copyState: "none"
    function copy(line) {
        Store.act("launcher.launch", { id: "calc:" + line }, function (m) {
            ks.copyState = m.t === "done" ? "copied" : "error: " + Store.actError(m, "keys.copy_failed")
        })
    }

    function line(kind, text) { return { kind: kind, text: text } }
    // The lines to show: [{kind: "dim"|"fg"|"ok"|"error", text}].
    readonly property var lines: {
        var d = ks.doc
        var out = []
        if (d === undefined) return ks.on ? [ks.line("dim", I18n.tr("keys.status.waiting"))] : []
        var path = ks.tilde(d.file || "")
        // Not ours to write: said whether or not writing is on (Home-Manager's keys are the ones in effect).
        if (ks.st === "managed") return [ks.line("fg", I18n.fmt("keys.status.managed", { path: path }))]
        if (ks.st === "foreign") return [ks.line(ks.on ? "error" : "dim", I18n.fmt("keys.status.foreign", { path: path }))]
        if (!ks.on) return []
        if (ks.st === "unsupported")
            return [ks.line("dim", d.compositor ? I18n.fmt("keys.status.unsupported", { compositor: d.compositor })
                                                : I18n.tr("keys.status.no_compositor"))]
        if (ks.st === "error") {
            out.push(ks.line("error", "✕ " + I18n.fmt(d.error || "keys.error.write_failed", { detail: d.detail || "" })))
            return out
        }
        if (ks.st === "written")
            out.push(ks.line("dim", I18n.fmt(d.changed === false ? "keys.status.same" : "keys.status.written", { path: path })))
        if (ks.leftOut > 0) out.push(ks.line("error", "⊘ " + I18n.fmt("keys.status.left_out", { n: ks.leftOut })))
        if (d.include && d.include.present)
            out.push(ks.line("ok", "✓ " + I18n.fmt("keys.status.included", { file: ks.tilde(d.include.file) })))
        // Sway applies a changed config only on reload (no watcher of its own): said, so the keys are not taken for live.
        if (ks.st === "written" && d.compositor === "sway") out.push(ks.line("dim", I18n.tr("keys.status.reload.sway")))
        return out
    }
    readonly property bool needsInclude: ks.on && ks.st === "written" && !!ks.doc.include && ks.doc.include.present !== true

    Repeater {
        model: ks.lines
        delegate: Text {
            required property var modelData
            width: ks.width
            wrapMode: Text.WordWrap
            color: modelData.kind === "error" ? Theme.error : (modelData.kind === "fg" ? Theme.fg : Theme.dim)
            font.pixelSize: Theme.fs - 2
            font.family: Theme.fam(text, Theme.families)
            text: modelData.text
        }
    }
    // The include line niri's config still needs, with Copy.
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        visible: ks.needsInclude
        width: ks.width
        wrapMode: Text.WordWrap
        color: Theme.fg
        font.pixelSize: Theme.fs - 2
        font.family: Theme.fam(text, Theme.families)
        text: ks.needsInclude ? "↳ " + I18n.fmt("keys.status.add_include." + (ks.doc.compositor || "niri"), { file: ks.tilde(ks.doc.include.file) }) : ""
    }
    Row {
        visible: ks.needsInclude
        width: ks.width
        spacing: Theme.gap
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - copyKey.width - parent.spacing
            height: incText.implicitHeight + Theme.gap
            radius: Theme.rSm
            color: Theme.surface
            border.width: 1
            border.color: Theme.containerHigh
            Text {
                id: incText
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.gap
                width: parent.width - 2 * Theme.gap
                elide: Text.ElideRight
                color: Theme.fg
                font.pixelSize: Theme.fs - 1
                font.family: "monospace"
                text: ks.needsInclude ? ks.doc.include.line : ""
            }
        }
        Button {
            id: copyKey
            objectName: "copy:keys-include"
            anchors.verticalCenter: parent.verticalCenter
            label: ks.copyState === "copied" ? I18n.tr("keys.copied") : I18n.tr("keys.copy")
            enabled: Store.live
            onClicked: ks.copy(ks.doc.include.line)
        }
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        visible: ks.copyState.indexOf("error") === 0
        width: ks.width
        wrapMode: Text.WordWrap
        color: Theme.error
        font.pixelSize: Theme.fs - 2
        font.family: Theme.fam(text, Theme.families)
        text: "✕ " + ks.copyState.substring(7)
    }
}
