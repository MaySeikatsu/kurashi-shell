import QtQuick
import "../core"
import "../components"

// Profiles: list (profile.list), diff before switching (profile.preview), load, save current.
// Every number shown comes from the daemon's answers; nothing is computed here.
Flickable {
    id: p
    property var profiles: []
    property string selected: ""
    property var diff: null          // null = nothing previewed yet
    property string message: ""
    property bool failed: false
    property string saveName: ""

    contentWidth: width
    contentHeight: col.implicitHeight + Theme.pad * 2
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function fail(m) { failed = true; message = m.msg || m.kind || "" }
    function refresh() {
        Store.act("profile.list", {}, function (m) {
            if (m.t === "done") p.profiles = (m.data && m.data.profiles) || []
            else p.fail(m)
        })
    }
    function preview(name) {
        selected = name
        diff = null
        message = ""
        Store.act("profile.preview", { name: name }, function (m) {
            if (m.t === "done") { p.diff = (m.data && m.data.diff) || []; p.failed = false }
            else p.fail(m)
        })
    }
    function load() {
        Store.act("profile.load", { name: selected }, function (m) {
            p.failed = m.t !== "done"
            p.message = p.failed ? (m.msg || "") : I18n.tr("settings.ui.profile_loaded")
            if (!p.failed) p.preview(p.selected)
        })
    }
    function save() {
        var n = saveName.trim()
        if (n === "") return
        Store.act("profile.save", { name: n }, function (m) {
            p.failed = m.t !== "done"
            p.message = p.failed ? (m.msg || "") : I18n.tr("settings.ui.profile_saved")
            if (!p.failed) { p.saveName = ""; p.refresh() }
        })
    }
    // Public so the test hook can drive the page like a click would.
    function select(name) { preview(name) }

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

        Text {
            color: Theme.accent
            font.pixelSize: Theme.fsTitle
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.profiles")
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
                    required property var modelData
                    readonly property bool on: modelData.name === p.selected
                    implicitWidth: n.implicitWidth + 2 * Theme.pad + (b.visible ? b.implicitWidth + Theme.gap : 0)
                    implicitHeight: 30
                    radius: Theme.rSm
                    color: on ? Theme.accent : Theme.containerHigh
                    border.width: 1
                    border.color: Theme.outline
                    Text {
                        id: n
                        x: Theme.pad
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: modelData.name
                    }
                    Chip {
                        id: b
                        visible: modelData.bundled === true
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.gap / 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("settings.ui.bundled")
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: p.preview(modelData.name)
                    }
                }
            }
        }

        // Diff of the selected profile against what is in effect now.
        Column {
            visible: p.selected !== ""
            width: parent.width
            spacing: Theme.gap
            Text {
                color: Theme.dim
                font.pixelSize: Theme.fs
                font.bold: true
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("settings.ui.diff_title") + " " + p.selected
            }
            Text {
                visible: p.diff !== null && p.diff.length === 0
                color: Theme.dim
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("settings.ui.no_changes")
            }
            Repeater {
                model: p.diff || []
                delegate: Row {
                    required property var modelData
                    spacing: Theme.gap
                    Text {
                        width: 240
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr(Store.labelOf(modelData.key)) + (modelData.output ? " (" + modelData.output + ")" : "")
                    }
                    Text {
                        color: Theme.dim
                        font.pixelSize: Theme.fs
                        text: modelData.before ? Store.displayValue(modelData.before.value) : "—"
                    }
                    ProvenanceChip { prov: modelData.before }
                    Text { color: Theme.dim; font.pixelSize: Theme.fs; text: "→" }
                    Text {
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        text: modelData.after ? Store.displayValue(modelData.after.value) : "—"
                    }
                    ProvenanceChip { prov: modelData.after }
                }
            }
            Button {
                primary: true
                enabled: p.diff !== null && Store.live
                label: I18n.tr("settings.ui.load")
                onClicked: p.load()
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
                value: p.saveName
                placeholder: I18n.tr("settings.ui.save_name")
                onAccepted: t => p.saveName = t
            }
            Button {
                enabled: p.saveName.trim() !== "" && Store.live
                label: I18n.tr("settings.ui.save")
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
