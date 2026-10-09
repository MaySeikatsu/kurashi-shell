import QtQuick
import "../core"
import "../components"

// Profiles (UX brief, settings 6): a profile is a set of settings with an origin (bundled, or yours). Loading one shows
// what would change first. The header of the selected profile counts the settings that differ from the current ones,
// and offers Show (the list), Save (the current settings under its name) and Revert (load it). Every number and every
// line comes from the daemon's answers (profile.preview, profile.save, config.profiles); nothing is computed here, except
// the count of the answer's lines.
Flickable {
    id: p
    // The list is the daemon's `config.profiles` (K27): pushed, and current when a profile file appears or goes. A daemon
    // without that field gets `profile.list` once per connection instead.
    property var listed: []
    readonly property bool pushed: Store.config.profiles !== undefined
    readonly property var profiles: pushed ? Store.config.profiles : listed
    property string selected: ""
    property var diff: null          // null = nothing previewed yet
    property bool showDiff: true
    property string message: ""
    property bool failed: false
    property string saveName: ""
    // A save under the name of a profile that exists needs a second press (it replaces the file).
    property bool replacing: false

    readonly property int differ: diff ? diff.length : 0
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
            else { p.failed = true; p.message = Store.actError(m, "settings.err.profile_list") }
        })
    }
    function preview(name) {
        selected = name
        diff = null
        message = ""
        replacing = false
        Store.act("profile.preview", { name: name }, function (m) {
            if (m.t === "done") { p.diff = (m.data && m.data.diff) || []; p.failed = false }
            else { p.failed = true; p.message = Store.actError(m, "settings.err.profile_preview") }
        })
    }
    function load() {
        Store.act("profile.load", { name: selected }, function (m) {
            p.failed = m.t !== "done"
            // The preview clears the message, so it runs first and the outcome is set after it.
            if (!p.failed) p.preview(p.selected)
            p.message = p.failed ? Store.actError(m, "settings.err.profile_load") : I18n.tr("settings.ui.profile_loaded")
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
            p.message = p.failed ? Store.actError(m, "settings.err.profile_save") : I18n.tr("settings.ui.profile_saved")
            if (!p.failed) { p.saveName = ""; p.refresh(); if (n === p.selected) p.preview(n) }
        })
    }
    // Public so the test hook can drive the page like a click would.
    function select(name) { preview(name) }
    // The line of one difference: what it is now, what the profile sets it to, and that Nix decides it instead.
    function nixHeld(key) {
        var q = Store.prov(key)
        return !!q && Store.isNix(q.source)
    }
    function origin(profile) {
        return I18n.tr(profile.bundled === true ? "settings.ui.origin_bundled" : "settings.ui.origin_yours")
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
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.profiles_help")
        }
        Text {
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
                    Keys.onReturnPressed: event => { p.preview(tile.modelData.name); event.accepted = true }
                    Keys.onEnterPressed: event => { p.preview(tile.modelData.name); event.accepted = true }
                    Keys.onSpacePressed: event => { p.preview(tile.modelData.name); event.accepted = true }
                    Accessible.role: Accessible.Button
                    Accessible.name: tile.modelData.name + ", " + p.origin(tile.modelData)
                    Text {
                        id: n
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
                        onClicked: p.preview(tile.modelData.name)
                    }
                    FocusRing {
                        anchors.fill: parent
                        shown: tile.activeFocus
                        corner: tile.radius
                    }
                }
            }
        }

        // The header of the selected profile (UX brief, settings 6): "Kanso · 3 settings differ — Show / Save / Revert".
        Column {
            visible: p.selected !== ""
            width: parent.width
            spacing: Theme.gap
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                font.family: Theme.fam(text, Theme.families)
                text: p.diff === null ? p.selected
                    : I18n.fmt(p.differ === 0 ? "settings.ui.profile_none_differ" : "settings.ui.profile_differ",
                               { name: p.selected, n: p.differ })
            }
            Row {
                spacing: Theme.gap
                Button {
                    label: p.showDiff ? I18n.tr("settings.ui.profile_hide") : I18n.tr("settings.ui.profile_show")
                    enabled: p.diff !== null
                    onClicked: p.showDiff = !p.showDiff
                }
                Button {
                    label: p.replacing ? I18n.tr("settings.ui.profile_replace") : I18n.tr("settings.ui.save")
                    enabled: Store.live && p.exists
                    onClicked: p.save(p.selected)
                }
                Button {
                    primary: true
                    label: I18n.tr("settings.ui.profile_revert")
                    enabled: p.diff !== null && Store.live
                    onClicked: p.load()
                }
            }

            // The differences, each with what it is now and what the profile sets (with their layers).
            Column {
                visible: p.showDiff && p.diff !== null
                width: parent.width
                spacing: Theme.gap / 2
                Text {
                    visible: p.diff !== null && p.diff.length === 0
                    color: Theme.dim
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr("settings.ui.no_changes")
                }
                Repeater {
                    model: p.diff || []
                    delegate: Item {
                        required property var modelData
                        width: col.width
                        height: Math.max(lbl.implicitHeight, Theme.controlH) + (p.nixHeld(modelData.key) ? 16 : 0)
                        Text {
                            id: lbl
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.topMargin: 6
                            width: 260
                            elide: Text.ElideRight
                            color: Theme.fg
                            font.pixelSize: Theme.fs
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.tr(Store.labelOf(modelData.key)) + (modelData.output ? " (" + modelData.output + ")" : "")
                        }
                        Row {
                            id: now
                            x: 276
                            anchors.top: parent.top
                            anchors.topMargin: 4
                            spacing: Theme.gap
                            Text {
                                height: Theme.controlH - 8
                                verticalAlignment: Text.AlignVCenter
                                color: Theme.dim
                                font.pixelSize: Theme.fs
                                font.family: Theme.fam(text, Theme.families)
                                text: modelData.before ? Store.displayValue(modelData.before.value) : I18n.tr("settings.ui.not_set")
                            }
                            ProvenanceChip {
                                visible: !!modelData.before
                                prov: modelData.before ?? ({})
                                key: modelData.key
                                output: modelData.output ?? ""
                            }
                            Text {
                                height: Theme.controlH - 8
                                verticalAlignment: Text.AlignVCenter
                                color: Theme.dim
                                font.pixelSize: Theme.fs
                                text: "→"
                            }
                            Text {
                                height: Theme.controlH - 8
                                verticalAlignment: Text.AlignVCenter
                                color: Theme.fg
                                font.pixelSize: Theme.fs
                                font.family: Theme.fam(text, Theme.families)
                                text: modelData.after ? Store.displayValue(modelData.after.value) : I18n.tr("settings.ui.not_set")
                            }
                        }
                        Text {
                            visible: p.nixHeld(modelData.key)
                            anchors.left: parent.left
                            anchors.leftMargin: 276
                            anchors.top: now.bottom
                            color: Theme.dim
                            font.pixelSize: Theme.fs - 2
                            font.family: Theme.fam(text, Theme.families)
                            text: "⊘ " + I18n.tr("settings.ui.not_applied_nix")
                        }
                    }
                }
                Text {
                    visible: p.diff !== null && p.diff.length > 0
                    width: parent.width
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
                enabled: p.saveName.trim() !== "" && Store.live
                label: p.replacing ? I18n.tr("settings.ui.profile_replace") : I18n.tr("settings.ui.save")
                onClicked: p.save()
            }
        }
        Text {
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
