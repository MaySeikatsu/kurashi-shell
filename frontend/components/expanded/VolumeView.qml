import QtQuick
import "../../core"
import ".."

// The expanded view of the volume face (K24; island brief 5): the master level with its read-back and mute; the output
// devices (a list when several, the default marked in text, a click makes one the default); the microphone (its mute, and
// the input list when several); and the applications that play sound, each with its level and mute. No audio server reads
// as such, with no level drawn (Shōjiki). The sliders are optimistic like the Bar's: the knob keeps the daemon's level until
// it answers. An application's level is sent on release (or per key press), never per frame of a drag. Watches svc.audio
// only while on screen (Ma).
Column {
    id: view
    width: parent.width
    spacing: Theme.gap

    Watch { doc: "svc.audio" }
    readonly property var d: Store.docs["svc.audio"] || ({})
    readonly property bool avail: d.available !== false
    readonly property bool muted: d.muted === true
    readonly property real level: Math.max(0, Math.min(1, d.volume ?? 0))
    readonly property string origin: "qs:stage"
    readonly property var sinks: avail && d.sinks ? d.sinks : []
    readonly property var sources: avail && d.sources ? d.sources : []
    readonly property var source: avail && d.source ? d.source : null
    readonly property var streams: avail && d.streams ? d.streams : []
    property string errText: ""
    Refusal { id: refusal }

    function act(action, args, msg) {
        view.errText = ""
        Store.act(action, args, function (done, err) { if (err) view.errText = refusal.text(err, msg) })
    }
    // A device's name for a list: its description, else its PulseAudio name.
    function nameOf(o) { return String(o.description || o.name || "") }

    // One device of a list: a radio-like row. The current one carries its "Default" in text, not in colour alone.
    component DeviceRow: Rectangle {
        id: row
        required property string label
        required property bool current
        signal chosen()
        width: view.width
        height: Theme.controlH
        radius: Theme.rSm
        color: !row.current && hover.hovered ? Theme.containerHigh : "transparent"
        activeFocusOnTab: true
        Keys.onReturnPressed: { if (!row.current) row.chosen() }
        Keys.onEnterPressed: { if (!row.current) row.chosen() }
        Keys.onSpacePressed: { if (!row.current) row.chosen() }
        Accessible.role: Accessible.RadioButton
        Accessible.name: row.label
        Accessible.checked: row.current
        Text {
            anchors { left: parent.left; right: tag.left; leftMargin: Theme.gap; rightMargin: Theme.gap; verticalCenter: parent.verticalCenter }
            elide: Text.ElideRight
            color: row.current ? Theme.fg : Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: row.label
        }
        Text {
            id: tag
            anchors { right: parent.right; rightMargin: Theme.gap; verticalCenter: parent.verticalCenter }
            visible: row.current
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("island.quick.audio.default")
        }
        HoverHandler { id: hover }
        TapHandler { enabled: !row.current; onTapped: row.chosen() }
        FocusRing { anchors.fill: parent; shown: row.activeFocus; corner: Theme.rSm }
    }

    Text {
        width: view.width
        color: Theme.fg
        font.pixelSize: Theme.fsTitle
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.volume.heading")
    }
    StaleNote { face: "volume" }
    Row {
        width: view.width
        spacing: Theme.gap
        IconButton {
            id: mute
            glyph: view.muted ? "⊘" : "♪"
            a11y: I18n.tr(view.muted ? "island.volume.unmute" : "island.volume.mute")
            enabled: view.avail
            onClicked: view.act("audio.mute.toggle", {}, "island.volume.failed")
        }
        Slider {
            height: mute.height
            width: view.width - mute.width - readout.width - 2 * Theme.gap
            value: view.level
            unavailable: !view.avail
            fill: view.muted ? Theme.dim : Theme.accent
            a11y: I18n.tr("island.volume.heading")
            onMoved: v => Store.intent("audio.volume", v, view.origin)
        }
        Text {
            id: readout
            width: 64
            height: mute.height
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            color: view.muted ? Theme.dim : Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: !view.avail ? "" : (view.muted ? I18n.tr("frontend.volume.muted") : Math.round(view.level * 100) + "%")
        }
    }
    Text {
        visible: !view.avail
        width: view.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("frontend.volume.unavailable")
    }

    // Output: several devices are a list; one is named; none says so.
    Text {
        visible: view.avail
        width: view.width
        color: Theme.dim
        font.pixelSize: Theme.fsLabel
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.volume.output")
    }
    Repeater {
        model: view.sinks.length > 1 ? view.sinks : []
        delegate: DeviceRow {
            required property var modelData
            label: view.nameOf(modelData)
            current: modelData["default"] === true
            onChosen: view.act("audio.sink.default", {id: modelData.id}, "island.quick.audio.failed")
        }
    }
    Text {
        visible: view.avail && view.sinks.length === 1
        width: view.width
        elide: Text.ElideRight
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: view.sinks.length === 1 ? view.nameOf(view.sinks[0]) : ""
    }
    Text {
        visible: view.avail && view.sinks.length === 0
        width: view.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.audio.none")
    }

    // Microphone: its mute (the daemon has no level for it to set), and the input list when several.
    Text {
        visible: view.avail
        width: view.width
        color: Theme.dim
        font.pixelSize: Theme.fsLabel
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.volume.input")
    }
    Row {
        visible: view.avail && view.source !== null
        width: view.width
        spacing: Theme.gap
        IconButton {
            id: micMute
            glyph: view.source && view.source.muted === true ? "⊘" : "●"
            a11y: I18n.tr(view.source && view.source.muted === true ? "island.volume.input.unmute" : "island.volume.input.mute")
            onClicked: view.act("audio.mic.mute.toggle", {}, "island.volume.input.failed")
        }
        Text {
            width: view.width - micMute.width - micState.width - 2 * Theme.gap
            height: micMute.height
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: view.source === null ? "" : (view.sources.length > 1 ? "" : view.nameOf(view.source))
        }
        Text {
            id: micState
            width: 64
            height: micMute.height
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            color: view.source && view.source.muted === true ? Theme.dim : Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: view.source && view.source.muted === true ? I18n.tr("island.volume.muted") : I18n.tr("island.volume.input.live")
        }
    }
    Repeater {
        model: view.sources.length > 1 ? view.sources : []
        delegate: DeviceRow {
            required property var modelData
            label: view.nameOf(modelData)
            current: modelData["default"] === true
            onChosen: view.act("audio.source.default", {id: modelData.id}, "island.volume.input.failed")
        }
    }
    Text {
        visible: view.avail && view.source === null
        width: view.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.volume.input.none")
    }

    // Applications that play sound: each with its mute and its level (0 to 150 %, the daemon's range; the knob spans it).
    Text {
        visible: view.avail
        width: view.width
        color: Theme.dim
        font.pixelSize: Theme.fsLabel
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.volume.apps")
    }
    Repeater {
        model: view.streams
        delegate: Row {
            id: stream
            required property var modelData
            readonly property bool silent: modelData.muted === true
            readonly property real vol: modelData.volume ?? 0
            width: view.width
            spacing: Theme.gap
            Text {
                width: 96
                height: Theme.controlH
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: stream.modelData.app ?? ""
            }
            IconButton {
                glyph: stream.silent ? "⊘" : "♪"
                a11y: I18n.tr(stream.silent ? "island.volume.app.unmute" : "island.volume.app.mute").replace("{app}", stream.modelData.app ?? "")
                onClicked: view.act("audio.stream.mute", {id: stream.modelData.id}, "island.volume.app.failed")
            }
            Slider {
                id: streamSlider
                width: view.width - 96 - 28 - streamReadout.width - 3 * Theme.gap
                height: Theme.controlH
                value: Math.min(1, stream.vol / 1.5)
                fill: stream.silent ? Theme.dim : Theme.accent
                a11y: stream.modelData.app ?? ""
                // A drag moves the knob; its end (release) or a key press is the one action.
                onMoved: v => { if (!streamSlider.dragging) view.act("audio.stream.volume", {id: stream.modelData.id, value: v * 1.5}, "island.volume.app.failed") }
            }
            Text {
                id: streamReadout
                width: 44
                height: Theme.controlH
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                color: stream.silent ? Theme.dim : Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: stream.silent ? I18n.tr("island.volume.muted") : Math.round(stream.vol * 100) + "%"
            }
        }
    }
    Text {
        visible: view.avail && view.streams.length === 0
        width: view.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.volume.apps.none")
    }
    Text {
        visible: view.errText !== ""
        width: view.width
        wrapMode: Text.WordWrap
        color: Theme.error
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: view.errText
    }
}
