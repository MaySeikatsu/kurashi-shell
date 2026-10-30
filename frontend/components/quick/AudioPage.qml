import QtQuick
import "../../core"
import "../expanded"
import ".."

// The audio page (docs/ux/quick-settings.md, Design 2): the output (its level, the sound switch, and the outputs when there
// is a real choice), the input (microphone switch, its level, the inputs when there is a choice) and each playing
// application's stream with its level and mute. The lists are ListModels updated in place, so the focus stays on the row
// the user chose. The requests come from QuickPanel, shared with the card's tiles and sliders.
Column {
    id: aud
    width: parent.width
    spacing: Theme.gap
    property var soundReq: null
    property var sinkReq: null
    property var micReq: null
    property var srcReq: null
    signal backRequested()

    function focusFirst() { header.forceActiveFocus() }

    readonly property var d: Store.docs["svc.audio"] || ({})
    readonly property bool avail: d.available === true
    readonly property var src: avail && d.source ? d.source : ({})
    property string errText: ""
    Refusal { id: refusal }

    // The three lists, as rows of plain values (a Repeater over a fresh array would rebuild the focused row).
    ListModel { id: sinkRows }
    ListModel { id: srcRows }
    ListModel { id: streamRows }
    function syncList(model, list) {
        for (var i = 0; i < list.length; i++) {
            var s = list[i]
            var r = {sid: Number(s.id), label: String(s.description || s.name || ""), isDefault: s["default"] === true}
            if (i < model.count) model.set(i, r)
            else model.append(r)
        }
        while (model.count > list.length) model.remove(model.count - 1)
    }
    function syncStreams() {
        var list = avail && d.streams ? d.streams : []
        for (var i = 0; i < list.length; i++) {
            var s = list[i]
            var r = {sid: Number(s.id), app: String(s.app || ""), vol: Number(s.volume || 0), muted: s.muted === true}
            if (i < streamRows.count) streamRows.set(i, r)
            else streamRows.append(r)
        }
        while (streamRows.count > list.length) streamRows.remove(streamRows.count - 1)
    }
    function syncAll() {
        syncList(sinkRows, avail && d.sinks ? d.sinks : [])
        syncList(srcRows, avail && d.sources ? d.sources : [])
        syncStreams()
    }
    onDChanged: syncAll()
    Component.onCompleted: syncAll()

    function setStream(id, v) {
        aud.errText = ""
        Store.act("audio.stream.volume", {id: id, value: Math.max(0, Math.min(1.5, v))}, function (done, err) {
            if (err) aud.errText = refusal.text(err, "island.quick.audio.stream_failed")
        })
    }
    function toggleStream(id, muted) {
        aud.errText = ""
        Store.act("audio.stream.mute", {id: id, on: !muted}, function (done, err) {
            if (err) aud.errText = refusal.text(err, "island.quick.audio.stream_failed")
        })
    }

    PageHeader {
        id: header
        title: I18n.tr("island.quick.tile.audio")
        backName: I18n.tr("island.quick.back")
        onBack: aud.backRequested()
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: !aud.avail
        width: aud.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.audio.unavailable")
    }

    // Output
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: aud.avail
        width: aud.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.audio.output")
    }
    LevelRow {
        visible: aud.avail
        width: aud.width
        glyph: "♪"
        value: Math.max(0, Math.min(1, Number(aud.d.volume || 0)))
        readout: aud.d.muted === true ? I18n.tr("island.quick.status.muted") : Math.round(Number(aud.d.volume || 0) * 100) + " %"
        a11y: I18n.tr("island.quick.level.volume")
        onMoved: v => Store.intent("audio.volume", v, "qs:quick")
    }
    Row {
        visible: aud.avail
        width: aud.width
        spacing: Theme.gap
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            width: parent.width - sound.width - Theme.gap
            anchors.verticalCenter: sound.verticalCenter
            elide: Text.ElideRight
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("island.quick.audio.sound")
        }
        ToggleSwitch {
            id: sound
            checked: aud.d.muted !== true
            enabled: aud.avail && !(aud.soundReq !== null && aud.soundReq.pending)
            label: I18n.tr("island.quick.audio.sound")
            onToggled: on => { if (aud.soundReq !== null) aud.soundReq.begin(on) }
        }
    }
    StateLine {
        width: aud.width
        req: aud.soundReq
        pendingText: I18n.tr("island.quick.changing")
    }
    Repeater {
        model: sinkRows
        delegate: ChoiceRow {
            required property int sid
            required property string label
            required property bool isDefault
            width: aud.width
            title: label
            radio: true
            checked: isDefault
            inert: sinkRows.count < 2
            sub: isDefault ? I18n.tr("island.quick.audio.default") : ""
            pending: aud.sinkReq !== null && aud.sinkReq.want === sid
            pendingText: I18n.tr("island.quick.changing")
            // The default is focusable (Tab walks every row) but choosing it again asks for nothing.
            onActivated: { if (!isDefault && aud.sinkReq !== null) aud.sinkReq.begin(sid) }
        }
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: aud.avail && sinkRows.count === 0
        width: aud.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.audio.none")
    }
    StateLine {
        width: aud.width
        req: aud.sinkReq
        pendingText: I18n.tr("island.quick.changing")
    }

    // Input
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: aud.avail
        width: aud.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.audio.input")
    }
    Row {
        visible: aud.avail
        width: aud.width
        spacing: Theme.gap
        Column {
            width: parent.width - mic.width - Theme.gap
            anchors.verticalCenter: mic.verticalCenter
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                width: parent.width
                elide: Text.ElideRight
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("island.quick.audio.microphone")
            }
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                width: parent.width
                visible: aud.src.id !== undefined
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("island.quick.audio.level").replace("{n}", String(Math.round(Number(aud.src.volume || 0) * 100)))
            }
        }
        ToggleSwitch {
            id: mic
            checked: aud.src.muted !== true
            enabled: aud.avail && !(aud.micReq !== null && aud.micReq.pending)
            label: I18n.tr("island.quick.audio.microphone")
            onToggled: on => { if (aud.micReq !== null) aud.micReq.begin(on) }
        }
    }
    StateLine {
        width: aud.width
        req: aud.micReq
        pendingText: I18n.tr("island.quick.changing")
    }
    Repeater {
        model: srcRows
        delegate: ChoiceRow {
            required property int sid
            required property string label
            required property bool isDefault
            width: aud.width
            title: label
            radio: true
            checked: isDefault
            inert: srcRows.count < 2
            sub: isDefault ? I18n.tr("island.quick.audio.default") : ""
            pending: aud.srcReq !== null && aud.srcReq.want === sid
            pendingText: I18n.tr("island.quick.changing")
            onActivated: { if (!isDefault && aud.srcReq !== null) aud.srcReq.begin(sid) }
        }
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: aud.avail && srcRows.count === 0
        width: aud.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.audio.no_input")
    }
    StateLine {
        width: aud.width
        req: aud.srcReq
        pendingText: I18n.tr("island.quick.changing")
    }

    // Applications: each playing stream, its level (0..150 %, the slider spans the full range) and mute.
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: aud.avail
        width: aud.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.audio.apps")
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: aud.avail && streamRows.count === 0
        width: aud.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.audio.no_apps")
    }
    Repeater {
        model: streamRows
        delegate: Column {
            id: stream
            required property int sid
            required property string app
            required property real vol
            required property bool muted
            width: aud.width
            spacing: Theme.xs
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                width: stream.width
                elide: Text.ElideRight
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: stream.app
            }
            Row {
                width: stream.width
                spacing: Theme.gap
                LevelRow {
                    width: stream.width - muteApp.width - Theme.gap
                    value: Math.min(1, stream.vol / 1.5)
                    readout: stream.muted ? I18n.tr("island.quick.status.muted") : Math.round(stream.vol * 100) + " %"
                    a11y: stream.app
                    onMoved: v => aud.setStream(stream.sid, v * 1.5)
                }
                Button {
                    id: muteApp
                    label: stream.muted ? I18n.tr("island.quick.audio.unmute_app") : I18n.tr("island.quick.audio.mute_app")
                    onClicked: aud.toggleStream(stream.sid, stream.muted)
                }
            }
        }
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: aud.errText !== ""
        width: aud.width
        wrapMode: Text.WordWrap
        color: Theme.error
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: aud.errText
    }
}
