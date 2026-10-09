import QtQuick
import "../core"
import "../components"

// Mods page (MODS.md, "The Settings Mods page"): one entry per mod from the daemon's `mods` document.
// The state shown is always the daemon's. A toggle only asks for `mod.enable` / `mod.disable`; the
// entry changes when the document does, and a refused request stays visible under its mod.
Flickable {
    id: p
    // mod id -> why its last request was refused, as text (the catalog text, or the generic line with its code).
    property var failures: ({})
    readonly property bool loaded: Store.mods.mods !== undefined
    readonly property var entries: loaded ? Store.mods.mods : []

    contentWidth: width
    contentHeight: col.implicitHeight + Theme.pad * 2
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // Public so the test hook can drive the page like a click would.
    function setEnabled(id, on) {
        var f = Object.assign({}, failures)
        delete f[id]
        failures = f
        Store.act(on ? "mod.enable" : "mod.disable", { id: id }, function (m) {
            if (m.t === "done") return
            var g = Object.assign({}, p.failures)
            g[id] = Store.actError(m, "settings.err.unknown_action")
            p.failures = g
        })
    }
    // Why an invalid mod cannot run: the catalog text of its reason and the file it concerns. The
    // parser's or the OS's own detail is English and stays out of the page.
    function problems(m) {
        return (m.errors || []).map(function (e) {
            return I18n.tr(e.key) + (e.path ? " (" + e.path + ")" : "")
        }).join("\n")
    }
    function joined(a) { return (a && a.length) ? a.join(", ") : I18n.tr("settings.ui.mod_none") }
    // "v0.1.0 · native · cost low": the facts the manifest gives, and no placeholder for the rest.
    function facts(m) {
        var parts = []
        if (m.version) parts.push("v" + m.version)
        if (m.tier) parts.push(I18n.tr("settings.ui.tier." + m.tier))
        if (m.cost) parts.push(I18n.tr("settings.ui.cost." + m.cost))
        return parts.join(" · ")
    }

    Column {
        id: col
        x: Theme.pad
        y: Theme.pad
        width: p.width - 2 * Theme.pad
        spacing: Theme.pad

        PageHeader {
            width: parent.width
            text: I18n.tr("settings.ui.mods")
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.mods_help")
        }
        Text {
            visible: p.loaded && p.entries.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.mods_empty")
        }
        Text {
            visible: !p.loaded && !Store.live
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.disconnected")
        }

        Repeater {
            model: p.entries
            delegate: Column {
                id: entry
                required property var modelData
                readonly property bool invalid: modelData.state === "invalid"
                readonly property string failure: p.failures[modelData.id] || ""
                width: col.width
                spacing: 4

                Item {
                    width: parent.width
                    height: Math.max(info.implicitHeight, tog.height)
                    Column {
                        id: info
                        anchors.left: parent.left
                        anchors.right: tog.left
                        anchors.rightMargin: Theme.pad
                        spacing: 2
                        Row {
                            spacing: Theme.gap
                            Text {
                                color: Theme.fg
                                font.pixelSize: Theme.fs
                                font.bold: true
                                font.family: Theme.fam(text, Theme.families)
                                text: I18n.tr(entry.modelData.name)
                            }
                            Chip {
                                text: I18n.tr("settings.ui.mod_state." + entry.modelData.state)
                                edge: entry.invalid ? Theme.error : Theme.outline
                                fg: entry.modelData.state === "enabled" ? Theme.fg : Theme.dim
                            }
                            Chip {
                                visible: entry.modelData.shadows_bundled === true
                                text: I18n.tr("settings.ui.mod_shadows")
                            }
                        }
                        Text {
                            visible: text !== ""
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: Theme.dim
                            font.pixelSize: Theme.fs - 1
                            font.family: Theme.fam(text, Theme.families)
                            text: entry.modelData.description ? I18n.tr(entry.modelData.description) : ""
                        }
                        Text {
                            visible: text !== ""
                            color: Theme.dim
                            font.pixelSize: Theme.fs - 2
                            font.family: Theme.fam(text, Theme.families)
                            text: p.facts(entry.modelData)
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: Theme.dim
                            font.pixelSize: Theme.fs - 2
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.tr("settings.ui.mod_caps") + ": " + p.joined(entry.modelData.capabilities)
                                + "   " + I18n.tr("settings.ui.mod_provides") + ": " + p.joined(entry.modelData.provides)
                        }
                    }
                    Toggle {
                        id: tog
                        objectName: "mod:" + entry.modelData.id
                        label: I18n.tr(entry.modelData.name)
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        checked: entry.modelData.state === "enabled"
                        enabled: Store.live && !entry.invalid
                        onToggled: v => p.setEnabled(entry.modelData.id, v)
                    }
                }
                Text {
                    visible: entry.invalid
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.error
                    font.pixelSize: Theme.fs - 2
                    font.family: Theme.fam(text, Theme.families)
                    text: p.problems(entry.modelData)
                }
                Text {
                    visible: entry.failure !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.error
                    font.pixelSize: Theme.fs - 2
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr("settings.ui.mods_failed") + ": " + entry.failure
                }
                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.containerHigh
                }
            }
        }
    }
}
