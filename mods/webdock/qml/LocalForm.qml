import QtQuick
import Quickshell
import qs.core
import qs.components

// The local chooser (W78; docs/ux/webdock.md "Local mode"): "+" in Local lists every view the enabled mods offer — each
// `panel:<name>` but the dock's own, and the desk cards `desk:<name>` with no panel of that name (the sidebar's rule,
// session 30). A press pins one (`webdock.add {url: "mod:<id>:<name>"}`) and opens it; one the dock has already opens.
// It reads the `mods` document the shell holds (no new subscription, no process) and unloads with the side panel.
Rectangle {
    id: form
    // The dock's pins (the document's, temporary pages too): a view already pinned opens instead of being added twice.
    property var pins: []
    property string error: ""
    signal opened(string pin)
    signal settingsPressed()
    signal cancelled()

    radius: Theme.rLg
    color: Theme.container
    Keys.onEscapePressed: form.cancelled()

    Watch { doc: "mods" }
    readonly property var choices: {
        var out = []
        var list = (Store.docs["mods"] && Store.docs["mods"].mods) || []
        for (var i = 0; i < list.length; i++) {
            var m = list[i]
            if (m.id === "webdock" || m.state !== "enabled") continue
            var q = m.qml || ({})
            var names = []
            for (var key in q) {
                if (key.indexOf("panel:") === 0) names.push(key.substring(6))
            }
            for (var k2 in q) {
                if (k2.indexOf("desk:") === 0 && q["panel:" + k2.substring(5)] === undefined) names.push(k2.substring(5))
            }
            for (var n = 0; n < names.length; n++) {
                var target = "mod:" + m.id + ":" + names[n]
                var label = I18n.tr(String(m.name || m.id))
                // (a view named apart from its mod — tasks' notes — is named by its view, its mod beside it)
                var own = names[n] !== m.id
                out.push({ target: target, title: own ? names[n].charAt(0).toUpperCase() + names[n].substring(1) : label,
                    sub: own ? label : "", pinned: pinOf(target) })
            }
        }
        return out
    }
    function pinOf(target) {
        for (var i = 0; i < pins.length; i++)
            if (pins[i].target === target && pins[i].temporary !== true) return pins[i].id
        return ""
    }
    function choose(c) {
        if (c.pinned !== "") { form.opened(c.pinned); return }
        form.error = ""
        Store.act("webdock.add", { url: c.target, title: c.title }, function (done, err) {
            if (err) form.error = err.msg || "webdock.add.invalid"
            else form.opened(done && done.data && done.data.pin ? String(done.data.pin) : "")
        })
    }
    function focusRow(i) {
        var it = rows.itemAt(Math.max(0, Math.min(rows.count - 1, i)))
        if (it) it.forceActiveFocus()
    }
    // (Tab into the panel from the strip, and the panel opening: the first row has the keyboard)
    onActiveFocusChanged: if (activeFocus) { if (rows.count > 0) focusRow(0); else noneKey.forceActiveFocus() }

    Column {
        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: Theme.gap

        Text {
            width: parent.width
            text: I18n.tr("webdock.local.title")
            color: Theme.fg
            font.pixelSize: Theme.fsLabel
            font.family: Theme.fam(text, Theme.families)
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Repeater {
            id: rows
            model: form.choices
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                width: parent.width
                height: Theme.controlH + 8
                radius: Theme.rSm
                color: row.activeFocus || rowHov.hovered ? Theme.containerHigh : Theme.surface
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: row.modelData.title + (row.modelData.sub !== "" ? " — " + row.modelData.sub : "")
                    + (row.modelData.pinned !== "" ? ", " + I18n.tr("webdock.local.pinned") : "")
                Keys.onReturnPressed: form.choose(row.modelData)
                Keys.onEnterPressed: form.choose(row.modelData)
                Keys.onSpacePressed: form.choose(row.modelData)
                Keys.onUpPressed: form.focusRow(row.index - 1)
                Keys.onDownPressed: form.focusRow(row.index + 1)
                Keys.onEscapePressed: form.cancelled()
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Theme.gap
                    spacing: Theme.gap
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "widgets"
                        glyph: "▦"
                        size: 18
                        color: Theme.dim
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.title
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.modelData.sub !== ""
                        text: row.modelData.sub
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.gap
                    visible: row.modelData.pinned !== ""
                    text: I18n.tr("webdock.local.pinned")
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                }
                FocusRing {
                    anchors.fill: parent
                    shown: row.activeFocus
                    corner: Theme.rSm
                }
                HoverHandler { id: rowHov }
                TapHandler { onTapped: form.choose(row.modelData) }
            }
        }
        // Empty: no enabled mod offers a view — said in words, with the way to turn one on.
        Text {
            width: parent.width
            visible: rows.count === 0
            wrapMode: Text.WordWrap
            text: I18n.tr("webdock.local.none")
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
        }
        Button {
            id: noneKey
            visible: rows.count === 0
            label: I18n.tr("webdock.local.mods")
            onClicked: form.settingsPressed()
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            visible: form.error !== ""
            text: I18n.tr(form.error)
            color: Theme.error
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }
        Button {
            label: I18n.tr("webdock.local.close")
            onClicked: form.cancelled()
        }
    }

    Component.onCompleted: { Qt.callLater(function () { form.forceActiveFocus() }); if (debugLog) rowLog.start() }

    // (test only, KURASHI_WEBDOCK_DEBUG=1: each choice and where its row is in the window — test-card.sh's part "local")
    readonly property bool debugLog: Quickshell.env("KURASHI_WEBDOCK_DEBUG") === "1"
    onChoicesChanged: if (debugLog) rowLog.restart()
    Timer {
        id: rowLog
        interval: 500
        onTriggered: {
            console.log("webdock-debug local count " + rows.count)
            for (var i = 0; i < rows.count; i++) {
                var r = rows.itemAt(i)
                var p = r.mapToItem(null, r.width / 2, r.height / 2)
                console.log("webdock-debug local " + r.modelData.target + " " + (r.modelData.pinned || "-") + " "
                    + Math.round(p.x) + " " + Math.round(p.y) + " " + Math.round(form.Window.width) + " " + Math.round(form.Window.height))
            }
        }
    }
}
