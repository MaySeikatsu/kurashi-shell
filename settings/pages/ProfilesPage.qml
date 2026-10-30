import QtQuick
import QtQuick.Controls.Basic as QQC
import Quickshell
import "../core"
import "../components"
import "../components/ProfileDiff.js" as ProfileDiff

// Profiles (UX brief, settings 6). A profile is a set of settings with an origin (bundled, or yours). Loading one is an
// overlay (B13): it changes the settings the profile sets and keeps every other change of yours. The review shows what
// changes, which of your changes it replaces, what Nix holds back, and how many of your changes stay. Export writes the
// selected profile for another machine; import reads a file, reviews it the same way and applies it on a second step.
// Every number and line comes from the daemon (profile.preview, profile.load, profile.save, profile.export,
// profile.import, config.profiles); this page only lays them out and names the paths its fields hold.
Flickable {
    id: p
    // Kinetic wheel and a grabbable scrollbar (session 17, docs/ux/settings.md).
    flickDeceleration: 2900
    maximumFlickVelocity: 7000
    KineticWheel { flick: p }
    QQC.ScrollBar.vertical: PageScrollBar {}
    // The list is the daemon's `config.profiles` (K27): pushed, and current when a profile file appears or goes. A daemon
    // without that field gets `profile.list` once per connection instead.
    property var listed: []
    readonly property bool pushed: Store.config.profiles !== undefined
    readonly property var profiles: pushed ? Store.config.profiles : listed
    property string selected: ""
    property var diff: null          // what loading the selected profile would change; null = not read (yet)
    property var held: []            // the entries a forced layer holds back (not_applied)
    property int keptUser: 0         // how many of your changes a load keeps
    property bool showDiff: true
    property bool reading: false     // the load preview is on its way
    property string message: ""      // the outcome of the last load, save or list
    property bool failed: false
    property string saveName: ""
    // A save under the name of a profile that exists needs a second press (it replaces the file).
    property bool replacing: false

    // Export: the selected profile to a file. The path starts at the export folder, under the data home.
    property string exportPath: ""
    property var exportLeftOut: null // null = no export shown; otherwise what it left out, and why
    property string exportMsg: ""
    property bool exportFailed: false

    // Import: the typed file name or path, the review of that file (null = none open) and the last apply's outcome.
    property string importText: ""
    property var review: null        // {name, path, entries, held, kept, diagnostics}
    property bool importing: false   // a review or an apply is on its way
    property string importMsg: ""
    property bool importFailed: false
    property var importHeld: []

    // The header counts the settings whose value changes; a line that only moves a setting to this profile is no difference.
    readonly property int differ: diff ? ProfileDiff.valueChanges(diff) : 0
    readonly property bool exists: selected !== "" && profiles.some(function (x) { return x.name === selected })

    contentWidth: width
    contentHeight: col.implicitHeight + Theme.pad * 2
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // Only for a daemon that does not push the list; the pushed one needs no request.
    function refresh() {
        if (pushed) return
        Store.act("profile.list", {}, function (m) {
            if (m.t === "done") p.listed = (m.data && m.data.profiles) || []
            else { p.failed = true; p.message = p.failure(m, "settings.err.profile_list") }
        })
    }
    // A refusal as the daemon sent it: the translated reason, with its code (UX brief, settings: error states). `what`
    // is the sentence for a refusal that carries no catalog key.
    function failure(m, what) {
        var code = m.msg || m.kind || "error"
        var text = I18n.has(code) ? I18n.tr(code) : I18n.tr(what)
        return I18n.fmt("settings.ui.error_code", { what: text, code: code })
    }
    // The export folder: where an export lands unless a path is typed, and where a typed file name is read from.
    function exportDir() {
        var data = Quickshell.env("XDG_DATA_HOME")
        if (!data) data = Quickshell.env("HOME") + "/.local/share"
        return data + "/kurashi/exports"
    }
    function exportDefault(name) { return name === "" ? "" : exportDir() + "/" + name + ".toml" }
    // A typed name is a file in the export folder; a path with a slash is sent as it is (the daemon wants it absolute).
    function importPathOf(text) {
        var t = text.trim()
        if (t === "" || t.indexOf("/") >= 0) return t
        return exportDir() + "/" + (t.slice(-5) === ".toml" ? t : t + ".toml")
    }

    // The load preview of a profile (profile.preview). A reply for a profile that is no longer selected is dropped.
    function preview(name) {
        diff = null
        held = []
        keptUser = 0
        message = ""
        replacing = false
        reading = true
        Store.act("profile.preview", { name: name }, function (m) {
            if (name !== p.selected) return
            p.reading = false
            if (m.t === "done") {
                var d = m.data || ({})
                p.diff = d.diff || []
                p.held = d.not_applied || []
                p.keptUser = d.kept_user || 0
                p.failed = false
            } else {
                p.failed = true
                p.message = p.failure(m, "settings.err.profile_preview")
            }
        })
    }
    // Choosing a profile (a tile, Return on it, the test hook): its preview, and an export starts from its name.
    function choose(name) {
        selected = name
        exportPath = exportDefault(name)
        exportLeftOut = null
        exportMsg = ""
        preview(name)
    }
    function load() {
        var name = selected
        Store.act("profile.load", { name: name }, function (m) {
            if (m.t !== "done") { p.failed = true; p.message = p.failure(m, "settings.err.profile_load"); return }
            // The preview is read again, as it now shows what is left to do; the outcome is set after it clears the line.
            p.preview(name)
            p.failed = false
            p.message = I18n.fmt("settings.ui.profile_loaded_kept", { n: (m.data && m.data.kept_user) || 0 })
        })
    }
    function save(name) {
        var n = (name === undefined ? saveName : name).trim()
        if (n === "") return
        if (!replacing && profiles.some(function (x) { return x.name === n })) {
            // An existing name: say what it does, and wait for the second press.
            replacing = true
            saveName = n
            message = I18n.fmt("settings.ui.profile_replace_ask", { name: n })
            failed = false
            return
        }
        replacing = false
        Store.act("profile.save", { name: n }, function (m) {
            p.failed = m.t !== "done"
            p.message = p.failed ? p.failure(m, "settings.err.profile_save") : I18n.tr("settings.ui.profile_saved")
            if (!p.failed) { p.saveName = ""; p.refresh(); if (n === p.selected) p.preview(n) }
        })
    }
    // Writes the selected profile to the path (profile.export). What it left out, and why, is listed under the field.
    function exportSelected() {
        var name = selected
        var path = exportPath.trim()
        if (name === "" || path === "") return
        exportMsg = ""
        exportFailed = false
        exportLeftOut = null
        Store.act("profile.export", { name: name, path: path }, function (m) {
            if (name !== p.selected) return
            if (m.t === "done") {
                var d = m.data || ({})
                p.exportLeftOut = d.left_out || []
                p.exportFailed = false
                p.exportMsg = I18n.fmt("settings.ui.export_done", { name: name, path: d.path || path })
            } else {
                p.exportFailed = true
                p.exportMsg = p.failure(m, "settings.err.profile_export")
            }
        })
    }
    // Reads the file and answers its review (profile.import without apply): nothing changes until Apply.
    function reviewImport() {
        var path = importPathOf(importText)
        if (path === "" || importing) return
        importing = true
        importMsg = ""
        importFailed = false
        importHeld = []
        Store.act("profile.import", { path: path }, function (m) {
            p.importing = false
            if (m.t !== "done") { p.importFailed = true; p.importMsg = p.failure(m, "settings.err.profile_import"); return }
            var d = m.data || ({})
            p.review = { name: d.name || "", path: path, entries: d.diff || [], held: d.not_applied || [],
                         kept: d.kept_user || 0, diagnostics: d.diagnostics || [] }
            // The review sits below a long load preview: the page scrolls to its buttons, which take the focus.
            Qt.callLater(function () { applyBtn.forceActiveFocus(); p.reveal(reviewButtons) })
        })
    }
    // Scrolls the least that brings the item into view (the focus can sit below the fold otherwise).
    function reveal(item) {
        var top = item.mapToItem(p.contentItem, 0, 0).y
        var bottom = top + item.height
        if (top < p.contentY) p.contentY = Math.max(0, top - Theme.pad)
        else if (bottom > p.contentY + p.height) p.contentY = Math.min(bottom - p.height + Theme.pad, p.contentHeight - p.height)
    }
    // Loads the reviewed file as one undoable change (profile.import with apply).
    function applyReview() {
        var r = review
        if (!r || importing) return
        importing = true
        Store.act("profile.import", { path: r.path, apply: true }, function (m) {
            p.importing = false
            p.review = null
            if (m.t === "done") {
                var d = m.data || ({})
                p.importFailed = false
                p.importMsg = I18n.fmt("settings.ui.import_done", { name: d.name || r.name, n: d.kept_user || 0 })
                p.importHeld = d.not_applied || []
                // The apply changed the settings: the selected profile's preview is read again.
                if (p.selected !== "") p.preview(p.selected)
            } else {
                p.importFailed = true
                p.importMsg = p.failure(m, "settings.err.profile_import")
            }
            Qt.callLater(function () { importField.focusInput(); p.reveal(importField) })
        })
    }
    // Esc on the review, or Cancel: the review goes, nothing has changed, and the field takes the focus back.
    function cancelReview() {
        review = null
        Qt.callLater(function () { importField.focusInput(); p.reveal(importField) })
    }
    // Public so the test hook can drive the page like a click would.
    function select(name) { choose(name) }
    function origin(profile) {
        return I18n.tr(profile.bundled === true ? "settings.ui.origin_bundled" : "settings.ui.origin_yours")
    }
    // One line of a held entry: the setting, and the reason the daemon gives (Nix, a pin, or the fallback text).
    function heldLine(e) {
        return "⊘ " + I18n.tr(Store.labelOf(e.key)) + (e.output ? " (" + e.output + ")" : "")
            + " — " + Store.forcedText({ reason: e.reason, forced_by: e.forced_by })
    }

    Component.onCompleted: if (Store.live) refresh()
    Connections {
        target: Store
        function onLiveChanged() { if (Store.live) p.refresh() }
    }

    Column {
        id: col
        x: Theme.pad
        y: Theme.pad
        width: p.width - 2 * Theme.pad
        spacing: Theme.pad

        PageHeader {
            width: parent.width
            text: I18n.tr("settings.ui.profiles")
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.profiles_help")
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            visible: p.profiles.length === 0
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.profiles_empty")
        }
        Flow {
            width: parent.width
            spacing: Theme.gap
            Repeater {
                model: p.profiles
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    readonly property bool on: modelData.name === p.selected
                    implicitWidth: n.implicitWidth + 2 * Theme.pad + o.implicitWidth + Theme.gap
                    implicitHeight: Theme.controlH
                    radius: Theme.rSm
                    color: on ? Theme.accent : Theme.containerHigh
                    border.width: 1
                    border.color: Theme.outline
                    activeFocusOnTab: true
                    Keys.onReturnPressed: event => { p.choose(tile.modelData.name); event.accepted = true }
                    Keys.onEnterPressed: event => { p.choose(tile.modelData.name); event.accepted = true }
                    Keys.onSpacePressed: event => { p.choose(tile.modelData.name); event.accepted = true }
                    Accessible.role: Accessible.Button
                    Accessible.name: tile.modelData.name + ", " + p.origin(tile.modelData)
                    Text {
                        id: n
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        x: Theme.pad
                        anchors.verticalCenter: parent.verticalCenter
                        // Text on the accent fill takes on_accent (4.5:1).
                        color: tile.on ? Theme.fgOnAccent : Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: tile.modelData.name
                    }
                    Chip {
                        id: o
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.gap / 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: p.origin(tile.modelData)
                        edge: tile.on ? Theme.fgOnAccent : Theme.outline
                        fg: tile.on ? Theme.fgOnAccent : Theme.dim
                        bg: tile.on ? Theme.accent : Theme.surface
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: p.choose(tile.modelData.name)
                    }
                    FocusRing {
                        anchors.fill: parent
                        shown: tile.activeFocus
                        corner: tile.radius
                    }
                }
            }
        }

        // The selected profile (UX brief, settings 6): "Kanso · 3 settings differ", then Show / Save / Revert.
        Column {
            visible: p.selected !== ""
            width: parent.width
            spacing: Theme.gap
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                font.family: Theme.fam(text, Theme.families)
                text: p.diff === null ? p.selected
                    : I18n.fmt(p.differ === 0 ? "settings.ui.profile_none_differ"
                               : p.differ === 1 ? "settings.ui.profile_differ_one" : "settings.ui.profile_differ",
                               { name: p.selected, n: p.differ })
            }
            Row {
                spacing: Theme.gap
                Button {
                    objectName: "profile-show"
                    label: p.showDiff ? I18n.tr("settings.ui.profile_hide") : I18n.tr("settings.ui.profile_show")
                    enabled: p.diff !== null
                    onClicked: p.showDiff = !p.showDiff
                }
                Button {
                    objectName: "profile-save"
                    label: p.replacing ? I18n.tr("settings.ui.profile_replace") : I18n.tr("settings.ui.save")
                    enabled: Store.live && p.exists
                    onClicked: p.save(p.selected)
                }
                Button {
                    objectName: "profile-revert"
                    primary: true
                    label: I18n.tr("settings.ui.profile_revert")
                    enabled: p.diff !== null && Store.live
                    onClicked: p.load()
                }
            }
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                visible: p.reading
                color: Theme.dim
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("settings.ui.profile_reading")
            }
            // The changes, with what they replace and what Nix holds back; the line under them counts what stays of yours.
            Column {
                id: loadBox
                visible: p.showDiff && p.diff !== null
                width: parent.width
                spacing: Theme.gap / 2
                ProfileReview {
                    width: loadBox.width
                    entries: p.diff || []
                    held: p.held
                    kept: p.keptUser
                }
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    width: loadBox.width
                    wrapMode: Text.WordWrap
                    color: Theme.dim
                    font.pixelSize: Theme.fs - 2
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr("settings.ui.profile_keep_hint")
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.containerHigh }

        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.bold: true
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.save_current")
        }
        Row {
            spacing: Theme.gap
            TextField {
                width: 220
                label: I18n.tr("settings.ui.save_name")
                value: p.saveName
                placeholder: I18n.tr("settings.ui.save_name")
                // Follows every edit, so Save is enabled as soon as a name is typed.
                onTyping: t => { p.saveName = t; p.replacing = false }
                onSubmitted: p.save()
            }
            Button {
                objectName: "profile-save-new"
                enabled: p.saveName.trim() !== "" && Store.live
                label: p.replacing ? I18n.tr("settings.ui.profile_replace") : I18n.tr("settings.ui.save")
                onClicked: p.save()
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.containerHigh }

        // Export (profile.export): a path to write, and what the file leaves out because it names this machine.
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.bold: true
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.export_head")
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs - 1
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.export_help")
        }
        Row {
            spacing: Theme.gap
            TextField {
                width: 420
                label: I18n.tr("settings.ui.export_file")
                value: p.exportPath
                placeholder: I18n.tr("settings.ui.export_file")
                onTyping: t => { p.exportPath = t }
                onSubmitted: p.exportSelected()
            }
            Button {
                objectName: "profile-export"
                label: I18n.tr("settings.ui.export")
                enabled: Store.live && p.selected !== "" && p.exportPath.trim() !== ""
                onClicked: p.exportSelected()
            }
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            visible: p.selected === ""
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs - 1
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.export_pick")
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            visible: p.exportMsg !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            color: p.exportFailed ? Theme.error : Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: p.exportMsg
        }
        Column {
            id: leftOutBox
            visible: p.exportLeftOut !== null
            width: parent.width
            spacing: Theme.gap / 2
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                visible: p.exportLeftOut !== null && p.exportLeftOut.length === 0
                width: leftOutBox.width
                color: Theme.dim
                font.pixelSize: Theme.fs - 1
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("settings.ui.export_none_left")
            }
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                visible: p.exportLeftOut !== null && p.exportLeftOut.length > 0
                width: leftOutBox.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fs - 1
                font.bold: true
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("settings.ui.export_left_out")
            }
            Repeater {
                model: p.exportLeftOut || []
                delegate: Text {
                    required property var modelData
                    width: leftOutBox.width
                    wrapMode: Text.WordWrap
                    color: Theme.fg
                    font.pixelSize: Theme.fs - 1
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr(Store.labelOf(modelData.key))
                        + (modelData.output ? " (" + modelData.output + ")" : "")
                        + " — " + I18n.tr(modelData.reason)
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.containerHigh }

        // Import (profile.import): a file is reviewed first, the same way as a load; Apply loads it, Cancel drops it.
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.bold: true
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.import_head")
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs - 1
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.import_help")
        }
        Row {
            spacing: Theme.gap
            TextField {
                id: importField
                width: 420
                label: I18n.tr("settings.ui.import_file")
                value: p.importText
                placeholder: I18n.tr("settings.ui.import_placeholder")
                onTyping: t => { p.importText = t }
                onSubmitted: p.reviewImport()
            }
            Button {
                objectName: "profile-review"
                label: I18n.tr("settings.ui.import_review")
                enabled: Store.live && p.importText.trim() !== "" && !p.importing
                onClicked: p.reviewImport()
            }
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            visible: p.importText.trim() !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs - 2
            font.family: Theme.fam(text, Theme.families)
            text: I18n.fmt("settings.ui.import_reads", { path: p.importPathOf(p.importText) })
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            visible: p.importing
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.import_reading")
        }
        // The review: the same lines as a load, then Apply or Cancel. Nothing changes before Apply; Esc cancels.
        Column {
            id: reviewBox
            visible: p.review !== null
            width: parent.width
            spacing: Theme.gap
            Keys.onEscapePressed: event => { p.cancelReview(); event.accepted = true }
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                width: reviewBox.width
                wrapMode: Text.WordWrap
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.bold: true
                font.family: Theme.fam(text, Theme.families)
                text: p.review ? I18n.fmt(ProfileDiff.valueChanges(p.review.entries) === 1
                                          ? "settings.ui.import_title_one" : "settings.ui.import_title",
                                          { name: p.review.name, n: ProfileDiff.valueChanges(p.review.entries) }) : ""
            }
            ProfileReview {
                width: reviewBox.width
                entries: p.review ? p.review.entries : []
                held: p.review ? p.review.held : []
                kept: p.review ? p.review.kept : 0
                diagnostics: p.review ? p.review.diagnostics : []
            }
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                width: reviewBox.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("settings.ui.import_keys")
            }
            Row {
                id: reviewButtons
                spacing: Theme.gap
                Button {
                    id: applyBtn
                    objectName: "profile-apply"
                    primary: true
                    label: I18n.tr("settings.ui.import_apply")
                    enabled: Store.live && !p.importing
                    onClicked: p.applyReview()
                }
                Button {
                    objectName: "profile-cancel"
                    label: I18n.tr("settings.ui.cancel")
                    enabled: !p.importing
                    onClicked: p.cancelReview()
                }
            }
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            visible: p.importMsg !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            color: p.importFailed ? Theme.error : Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: p.importMsg
        }
        // After an apply: what the file held back, as the apply answered it.
        Column {
            id: heldBox
            visible: p.review === null && p.importHeld.length > 0
            width: parent.width
            spacing: Theme.gap / 2
            Repeater {
                model: p.importHeld
                delegate: Text {
                    required property var modelData
                    width: heldBox.width
                    wrapMode: Text.WordWrap
                    color: Theme.dim
                    font.pixelSize: Theme.fs - 1
                    font.family: Theme.fam(text, Theme.families)
                    text: p.heldLine(modelData)
                }
            }
        }

        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            visible: p.message !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            color: p.failed ? Theme.error : Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: p.message
        }
    }
}
