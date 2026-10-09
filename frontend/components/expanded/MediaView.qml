import QtQuick
import "../../core"
import ".."

// The expanded view of the media face (K24; island brief 5): the art (a placeholder when there is none), title, artist
// and album, the player switcher when several players run, the progress, the transport, the output chip (quick settings,
// Audio), and the lyrics slot. The progress is interpolated from the position the daemon read, its time and the rate:
// it moves while the player plays, and the view says why when there is no progress (no position, a live stream). Seek is
// offered only where the player allows it (`can.seek`); a transport action the player forbids is disabled with the reason.
// Mod contributions (K28): `backdrop` behind the content (decorative, its contribution gates its own motion), `below`
// under the transport (lyrics). Watches svc.media and svc.audio only while on screen (Ma); the progress timer runs only
// while something plays and the view is shown.
Item {
    id: view
    width: parent.width
    implicitHeight: col.implicitHeight

    Watch { doc: "svc.media" }
    Watch { doc: "svc.audio" }
    readonly property var d: Store.docs["svc.media"] || ({})
    readonly property var audio: Store.docs["svc.audio"] || ({})
    readonly property bool unavailable: d.available === false
    readonly property bool idle: unavailable || (d.title ?? "") === ""
    readonly property bool playing: !idle && d.playing === true
    readonly property var players: d.players || []
    property string errText: ""
    Refusal { id: refusal }

    // The player's capabilities (PROTOCOL §8 svc.media `can`): true, false, or undefined when it does not say. Transport is
    // offered unless the player forbids it (the daemon refuses what it cannot do); seek is offered only when it allows it.
    // The flat flags of the first svc.media shape stand in while `can` is absent.
    function can(name) {
        var c = d.can
        if (c && c[name] !== undefined) return c[name] === true
        var flat = d["can_" + name]
        return flat === undefined ? undefined : flat === true
    }
    readonly property bool canSeek: can("seek") === true
    readonly property bool trackBlocked: !idle && (can("next") === false || can("prev") === false)
    readonly property bool playBlocked: !idle && can("play") === false && can("pause") === false

    // Progress. `position_us` was read at `position_at_ms` (wall clock); while playing, it advances at `rate`.
    readonly property bool hasPos: typeof d.position_us === "number" && typeof d.position_at_ms === "number"
    readonly property bool hasLen: typeof d.length_us === "number" && d.length_us > 0
    property real nowMs: Date.now()
    readonly property real posUs: {
        if (!hasPos) return 0
        var rate = typeof d.rate === "number" ? d.rate : 1
        var p = d.position_us + (playing ? Math.max(0, nowMs - d.position_at_ms) * 1000 * rate : 0)
        // Past the end, the reading is not extrapolated: the track has moved on, or the clocks differ. The next reading
        // (a track change, a seek, a play state) says which, so the view shows what was read rather than a guessed end.
        if (hasLen && p > d.length_us) return d.position_us
        return Math.max(0, p)
    }
    readonly property real frac: hasPos && hasLen ? posUs / d.length_us : 0
    onDChanged: nowMs = Date.now()
    Timer {
        // Once a second, and only while the position moves on screen (Ma).
        interval: 1000
        repeat: true
        running: view.visible && view.playing && view.hasPos
        onTriggered: view.nowMs = Date.now()
    }

    function fmt(us) {
        var s = Math.floor(us / 1000000), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60
        var mm = m < 10 && h > 0 ? "0" + m : "" + m
        var ss = sec < 10 ? "0" + sec : "" + sec
        return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss
    }
    function act(action, args) {
        view.errText = ""
        Store.act(action, args, function (done, err) {
            if (err) view.errText = refusal.text(err, "island.media.failed")
        })
    }
    function transport(action) { act(action, {}) }
    function seek(us) { act("media.seek", {offset_us: us}) }
    function selectPlayer(id) { act("media.player.select", {id: id}) }
    readonly property string reason: unavailable ? I18n.tr("island.media.unavailable")
        : idle ? ""
        : !hasPos ? I18n.tr("island.media.position.none")
        : !hasLen ? I18n.tr("island.media.live")
        : !canSeek ? I18n.tr("island.media.seek.none") : ""
    readonly property string transportReason: trackBlocked ? I18n.tr("island.media.transport.tracks")
        : playBlocked ? I18n.tr("island.media.transport.playback") : ""

    SlotHost { anchors.fill: parent; layout: "stack"; slot: "media.expanded.backdrop"; z: -1 }
    Column {
        id: col
        width: view.width
        spacing: Theme.gap

        Text {
            width: view.width
            color: Theme.fg
            font.pixelSize: Theme.fsTitle
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("island.media.heading")
        }
        StaleNote { face: "media" }
        Row {
            width: view.width
            spacing: Theme.gap
            Rectangle {
                id: artBox
                width: 56
                height: 56
                radius: Theme.rSm
                color: Theme.containerHigh
                clip: true
                Accessible.role: Accessible.Graphic
                Accessible.name: I18n.tr("island.media.art")
                Image {
                    id: art
                    anchors.fill: parent
                    visible: status === Image.Ready
                    // Decoded at display size (2x for a sharp edge), not at the cover's own size.
                    sourceSize: Qt.size(112, 112)
                    source: view.idle ? "" : (view.d.art_url ?? "")
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                }
                Text {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready
                    color: Theme.dim
                    font.pixelSize: Theme.fsTitle + 4
                    text: "♪"
                }
            }
            Column {
                width: view.width - artBox.width - Theme.gap
                spacing: Theme.xs
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: view.idle ? Theme.dim : Theme.fg
                    font.pixelSize: Theme.fs
                    font.bold: !view.idle
                    font.family: Theme.fam(text, Theme.families)
                    text: view.idle ? (view.unavailable ? "" : I18n.tr("island.media.idle")) : (view.d.title ?? "")
                }
                Text {
                    visible: !view.idle && (view.d.artist ?? "") !== ""
                    width: parent.width
                    elide: Text.ElideRight
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: view.d.artist ?? ""
                }
                Text {
                    visible: !view.idle && (view.d.album ?? "") !== ""
                    width: parent.width
                    elide: Text.ElideRight
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: view.d.album ?? ""
                }
            }
        }

        // The players, when several run: the active one is outlined, a playing one carries ▶. Pick one to control it.
        Flow {
            visible: view.players.length > 1
            width: view.width
            spacing: Theme.gap
            Repeater {
                model: view.players
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool active: modelData.active === true
                    implicitWidth: label.implicitWidth + 2 * Theme.pad
                    implicitHeight: Theme.controlH - 6
                    radius: Theme.rFull
                    color: active ? Theme.containerHigh : "transparent"
                    border.width: 1
                    border.color: active ? Theme.accent : Theme.outline
                    activeFocusOnTab: true
                    Keys.onReturnPressed: view.selectPlayer(modelData.id)
                    Keys.onEnterPressed: view.selectPlayer(modelData.id)
                    Keys.onSpacePressed: view.selectPlayer(modelData.id)
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.tr("island.media.player") + ": " + (modelData.name ?? "")
                    Accessible.checkable: true
                    Accessible.checked: active
                    Text {
                        id: label
                        anchors.centerIn: parent
                        color: chip.active ? Theme.fg : Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                        text: (modelData.playing === true ? "▶ " : "") + (modelData.name ?? "")
                    }
                    MouseArea { anchors.fill: parent; onClicked: view.selectPlayer(modelData.id) }
                    FocusRing { anchors.fill: parent; shown: chip.activeFocus; corner: chip.radius }
                }
            }
        }

        // Progress: the times at both ends and the bar between them, for a track (a length). The bar takes the seek only
        // where the player allows it. A live stream has no progress: the reason line below says so.
        Row {
            visible: view.hasPos && view.hasLen
            width: view.width
            spacing: Theme.gap
            Text {
                id: elapsed
                width: 44
                height: Theme.controlH
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
                color: Theme.fg
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: view.fmt(view.posUs)
            }
            Slider {
                id: seekBar
                visible: view.hasLen && view.canSeek
                width: view.width - elapsed.width - total.width - 2 * Theme.gap
                height: Theme.controlH
                value: view.frac
                a11y: I18n.tr("island.media.position")
                // Released or keyed: one action with the new place. The drag itself only moves the knob.
                onMoved: v => { if (!seekBar.dragging) view.act("media.set_position", {us: Math.round(v * view.d.length_us)}) }
            }
            Rectangle {
                visible: view.hasLen && !view.canSeek
                width: view.width - elapsed.width - total.width - 2 * Theme.gap
                height: 4
                anchors.verticalCenter: parent.verticalCenter
                radius: 2
                color: Theme.outline
                Rectangle { width: parent.width * view.frac; height: parent.height; radius: 2; color: Theme.accent }
            }
            Text {
                id: total
                visible: view.hasLen
                width: 44
                height: Theme.controlH
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: view.fmt(view.d.length_us ?? 0)
            }
        }
        Text {
            visible: view.reason !== ""
            width: view.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: view.reason
        }

        Row {
            id: transportRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.gap
            IconButton {
                visible: view.canSeek
                glyph: "−10"
                a11y: I18n.tr("island.media.seek.back")
                onClicked: view.seek(-10000000)
            }
            IconButton {
                glyph: "⏮"
                a11y: I18n.tr("island.media.prev")
                enabled: !view.idle && view.can("prev") !== false
                onClicked: view.transport("media.prev")
            }
            IconButton {
                glyph: view.playing ? "⏸" : "▶"
                a11y: I18n.tr(view.playing ? "island.media.pause" : "island.media.play")
                enabled: !view.idle && view.can(view.playing ? "pause" : "play") !== false
                onClicked: view.transport("media.play_pause")
            }
            IconButton {
                glyph: "⏭"
                a11y: I18n.tr("island.media.next")
                enabled: !view.idle && view.can("next") !== false
                onClicked: view.transport("media.next")
            }
            IconButton {
                visible: view.canSeek
                glyph: "+10"
                a11y: I18n.tr("island.media.seek.forward")
                onClicked: view.seek(10000000)
            }
        }
        Text {
            visible: view.transportReason !== ""
            width: view.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: view.transportReason
        }

        // The output chip: the default output, and a click opens quick settings (its Audio section).
        Rectangle {
            id: outChip
            width: view.width
            height: Theme.controlH
            radius: Theme.rFull
            color: Theme.containerHigh
            activeFocusOnTab: true
            readonly property var sink: view.audio.sink
            readonly property string outText: view.audio.available === false ? I18n.tr("island.volume.unavailable")
                : sink ? I18n.tr("island.media.output").replace("{name}", sink.description || sink.name || "")
                : I18n.tr("island.media.output.none")
            Keys.onReturnPressed: Store.act("quick.toggle")
            Keys.onEnterPressed: Store.act("quick.toggle")
            Keys.onSpacePressed: Store.act("quick.toggle")
            Accessible.role: Accessible.Button
            Accessible.name: outText
            Text {
                anchors { left: parent.left; right: parent.right; leftMargin: Theme.pad; rightMargin: Theme.pad; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight
                color: Theme.fg
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: outChip.outText
            }
            MouseArea { anchors.fill: parent; onClicked: Store.act("quick.toggle") }
            FocusRing { anchors.fill: parent; shown: outChip.activeFocus; corner: Theme.rFull }
        }

        SlotHost { slot: "media.expanded.below"; width: view.width }
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
}
