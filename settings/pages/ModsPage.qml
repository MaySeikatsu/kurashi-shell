import QtQuick
import "../core"
import "../components"

// Mods page (MODS.md, "The Settings Mods page"): one entry per mod from the daemon's `mods` document.
// The state shown is always the daemon's. A toggle only asks for `mod.enable` / `mod.disable`; the
// entry changes when the document does, and a refused request stays visible under its mod.
Flickable {
    id: p
    // mod id -> the daemon's message for the last refused request for that mod.
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
            g[id] = m.msg || m.kind || ""
            p.failures = g
        })
    }
    // Why an invalid mod cannot run, in the daemon's words: catalog key, file path, detail.
    function problems(m) {
        return (m.errors || []).map(function (e) {
            return I18n.tr(e.key) + (e.path ? " (" + e.path + ")" : "") + (e.detail ? ": " + e.detail : "")
        }).join("\n")
    }
    function joined(a) { return (a && a.length) ? a.join(", ") : I18n.tr("settings.ui.mod_none") }

    Column {
        id: col
        x: Theme.pad
        y: Theme.pad
        width: p.width - 2 * Theme.pad
        spacing: Theme.pad

        Text {
            color: Theme.accent
            font.pixelSize: Theme.fsTitle
            font.family: Theme.fam(text, Theme.families)
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
                            Text {
                                color: Theme.dim
                                font.pixelSize: Theme.fs - 2
                                font.family: "monospace"
                                text: entry.modelData.id
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
                            color: Theme.dim
                            font.pixelSize: Theme.fs - 2
                            font.family: Theme.fam(text, Theme.families)
                            text: (entry.modelData.version ? "v" + entry.modelData.version : "—")
                                + " · " + (entry.modelData.tier ? I18n.tr("settings.ui.tier." + entry.modelData.tier) : "—")
                                + " · " + (entry.modelData.cost ? I18n.tr("settings.ui.cost." + entry.modelData.cost) : "—")
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
                    text: I18n.tr("settings.ui.mods_failed") + ": " + I18n.tr(entry.failure)
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
