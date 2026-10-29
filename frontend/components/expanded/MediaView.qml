import QtQuick
import Quickshell.Widgets
import "../../core"
import ".."
import "../island"

// The expanded view of the media face (K24; island brief 5): the art (a placeholder when there is none), title, artist
// and album, the player switcher when several players run, the progress, the transport, the output chip (quick settings,
// Audio), and the lyrics slot. The progress is interpolated from the position the daemon read, its time and the rate:
// it moves while the player plays, and the view says why when there is no progress (no position, a live stream). Seek is
// offered only where the player allows it (`can.seek`); a transport action the player forbids is disabled with the reason.
// Mod contributions (K28): `backdrop` behind the content (decorative, its contribution gates its own motion), `below`
// under the transport (lyrics). Watches svc.media and svc.audio only while on screen (Ma); the progress timer runs only
// while something plays and the view is shown.
// W21 look: big rounded art beside the titles, the progress as a thick pill (a seek target only where seek is allowed),
// keycap transport keys with the play key tonal and larger, the output as a chip with its speaker icon.
// W24 (K48): the level bars are the live audio levels (`svc.audio.spectrum`, LevelBars watches it only while they show),
// and the hero sits on the cover's colours when the daemon has them.
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
    // The cover's colours, once the daemon extracted them for the shown track (K48 `art_colors`: bg, fg, accent).
    readonly property var artColors: !idle && d.art_colors && typeof d.art_colors.bg === "string" ? d.art_colors : null
    readonly property bool tinted: artColors !== null
    readonly property color heroFg: tinted ? artColors.fg : Theme.fg
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
        spacing: Theme.pad

        Text {
            width: view.width
            color: Theme.dim
            font.pixelSize: Theme.fsLabel
            font.weight: Theme.wMedium
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("island.media.heading")
        }
        StaleNote { face: "media" }
        // The hero: the art beside the titles and the level bars. With the cover's colours (`art_colors`, K48) it sits on
        // the cover's own tone, its text and bars in the colours the daemon checked for contrast (data colours, not
        // tokens); without them it is plain, on the card.
        RoundBox {
            id: hero
            width: view.width
            height: heroRow.implicitHeight + 2 * inset
            readonly property real inset: view.tinted ? Theme.pad : 0
            radius: Theme.rLg + 4
            color: view.tinted ? view.artColors.bg : "transparent"
            Behavior on color { enabled: Theme.springOn && view.visible; ColorAnimation { duration: 320 } }
            Row {
                id: heroRow
                x: hero.inset
                y: hero.inset
                width: view.width - 2 * hero.inset
                spacing: Theme.pad
                // The art, big and rounded; a tonal tile with the note when there is none.
                ClippingRectangle {
                    id: artBox
                    width: 96
                    height: 96
                    radius: Theme.rLg
                    color: Theme.selected
                    Accessible.role: Accessible.Graphic
                    Accessible.name: I18n.tr("island.media.art")
                    // I167: the cover is a picture: never under the relief, even with texture.text on.
                    readonly property var pictureOf: art.status === Image.Ready ? Window.window : null
                    onPictureOfChanged: pictureOf ? Light.addPicture(artBox, pictureOf) : Light.removePicture(artBox)
                    Component.onDestruction: Light.removePicture(artBox)
                    Image {
                        id: art
                        anchors.fill: parent
                        visible: status === Image.Ready
                        // Decoded at display size (2x for a sharp edge), not at the cover's own size.
                        sourceSize: Qt.size(192, 192)
                        source: view.idle ? "" : (view.d.art_url ?? "")
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                    }
                    Icon {
                        anchors.centerIn: parent
                        visible: art.status !== Image.Ready
                        name: "music_note"
                        glyph: "♪"
                        filled: true
                        size: 44
                        color: Theme.fgOnSelected
                    }
                }
                Column {
                    width: heroRow.width - artBox.width - Theme.pad
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.xs
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: view.idle ? Theme.dim : view.heroFg
                        font.pixelSize: Theme.fsTitle
                        font.weight: view.idle ? Theme.wRegular : Theme.wBold
                        font.family: Theme.fam(text, Theme.families)
                        text: view.idle ? (view.unavailable ? "" : I18n.tr("island.media.idle")) : (view.d.title ?? "")
                    }
                    Text {
                        visible: !view.idle && (view.d.artist ?? "") !== ""
                        width: parent.width
                        elide: Text.ElideRight
                        color: view.heroFg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: view.d.artist ?? ""
                    }
                    Text {
                        visible: !view.idle && (view.d.album ?? "") !== ""
                        width: parent.width
                        elide: Text.ElideRight
                        color: view.tinted ? view.heroFg : Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                        text: view.d.album ?? ""
                    }
                    LevelBars {
                        visible: !view.idle
                        running: view.playing && view.visible
                        color: view.tinted ? view.artColors.accent : Theme.accent
                        bars: 8
                        maxH: 14
                    }
                }
            }
        }

        // The players, when several run: the active one is tonal, a playing one carries ▶. Pick one to control it.
        Flow {
            visible: view.players.length > 1
            width: view.width
            spacing: Theme.gap
            Repeater {
                model: view.players
                delegate: Block {
                    id: chip
                    required property var modelData
                    readonly property bool active: modelData.active === true
                    implicitWidth: label.implicitWidth + 2 * Theme.pad
                    implicitHeight: Theme.controlH - 6 + Theme.shadowDy
                    radius: Theme.rFull
                    ringScale: 0.5
                    softScale: 0.4
                    fill: active ? Theme.selected : Theme.container
                    flatBorder: active ? "transparent" : Theme.outline
                    pressed: chipTap.pressed
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
                        color: chip.active ? Theme.fgOnSelected : Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.weight: chip.active ? Theme.wMedium : Theme.wRegular
                        font.family: Theme.fam(text, Theme.families)
                        text: (modelData.playing === true ? "▶ " : "") + (modelData.name ?? "")
                    }
                    MouseArea { id: chipTap; anchors.fill: parent; onClicked: view.selectPlayer(modelData.id) }
                    FocusRing { parent: chip.face; anchors.fill: parent; shown: chip.activeFocus; corner: Theme.rFull }
                }
            }
        }

        // Progress: a thick pill, the times under its ends, for a track (a length). It takes a seek (click, drag, arrows)
        // only where the player allows it. A live stream has no progress: the reason line below says so.
        Column {
            visible: view.hasPos && view.hasLen
            width: view.width
            spacing: Theme.xs
            Item {
                id: progress
                width: view.width
                height: 20
                // While dragging, the pill shows where the release will seek to.
                property real dragFrac: -1
                readonly property real shownFrac: Math.max(0, Math.min(1, dragFrac >= 0 ? dragFrac : view.frac))
                activeFocusOnTab: view.canSeek
                Accessible.role: Accessible.Slider
                Accessible.name: I18n.tr("island.media.position")
                Accessible.focusable: view.canSeek
                function seekTo(f) { view.act("media.set_position", {us: Math.round(Math.max(0, Math.min(1, f)) * view.d.length_us)}) }
                Keys.onLeftPressed: if (view.canSeek) view.seek(-5000000)
                Keys.onRightPressed: if (view.canSeek) view.seek(5000000)
                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 10
                    radius: 5
                    color: Qt.alpha(Theme.fg, 0.12)
                    Rectangle {
                        height: parent.height
                        radius: 5
                        width: progress.shownFrac > 0 ? Math.max(height, parent.width * progress.shownFrac) : 0
                        color: Theme.accent
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: view.canSeek
                    cursorShape: view.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPressed: m => progress.dragFrac = m.x / width
                    onPositionChanged: m => { if (pressed) progress.dragFrac = Math.max(0, Math.min(1, m.x / width)) }
                    onReleased: m => { progress.seekTo(m.x / width); progress.dragFrac = -1 }
                    onCanceled: progress.dragFrac = -1
                }
                FocusRing { anchors.fill: track; anchors.margins: -3; shown: progress.activeFocus; corner: 8 }
            }
            Item {
                width: view.width
                height: elapsed.implicitHeight
                Text {
                    id: elapsed
                    color: Theme.fg
                    font.pixelSize: Theme.fsCaption
                    font.features: { "tnum": 1 }
                    font.family: Theme.fam(text, Theme.families)
                    text: view.fmt(view.posUs)
                }
                Text {
                    anchors.right: parent.right
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.features: { "tnum": 1 }
                    font.family: Theme.fam(text, Theme.families)
                    text: "−" + view.fmt(Math.max(0, (view.d.length_us ?? 0) - view.posUs))
                }
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
            spacing: Theme.pad
            KeyButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: view.canSeek
                icon: "replay_10"
                glyph: "−10"
                a11y: I18n.tr("island.media.seek.back")
                onClicked: view.seek(-10000000)
            }
            KeyButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "skip_previous"
                glyph: "⏮"
                a11y: I18n.tr("island.media.prev")
                enabled: !view.idle && view.can("prev") !== false
                onClicked: view.transport("media.prev")
            }
            KeyButton {
                anchors.verticalCenter: parent.verticalCenter
                primary: true
                side: Theme.controlH + 16
                iconSize: Theme.fs + 18
                icon: view.playing ? "pause" : "play_arrow"
                glyph: view.playing ? "⏸" : "▶"
                a11y: I18n.tr(view.playing ? "island.media.pause" : "island.media.play")
                enabled: !view.idle && view.can(view.playing ? "pause" : "play") !== false
                onClicked: view.transport("media.play_pause")
            }
            KeyButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "skip_next"
                glyph: "⏭"
                a11y: I18n.tr("island.media.next")
                enabled: !view.idle && view.can("next") !== false
                onClicked: view.transport("media.next")
            }
            KeyButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: view.canSeek
                icon: "forward_10"
                glyph: "+10"
                a11y: I18n.tr("island.media.seek.forward")
                onClicked: view.seek(10000000)
            }
        }
        Text {
            visible: view.transportReason !== ""
            width: view.width
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: view.transportReason
        }

        // The output chip: the default output, and a click opens quick settings (its Audio section).
        Block {
            id: outChip
            width: view.width
            height: Theme.controlH + Theme.shadowDy
            radius: Theme.rFull
            ringScale: 0.5
            fill: Theme.containerHigh
            pressed: outTap.pressed
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
            Icon {
                id: spk
                anchors { left: parent.left; leftMargin: Theme.pad; verticalCenter: parent.verticalCenter }
                name: "speaker"
                glyph: "♫"
                filled: true
                size: Theme.fs + 4
                color: Theme.dim
            }
            Text {
                anchors { left: spk.right; right: parent.right; leftMargin: Theme.gap; rightMargin: Theme.pad; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight
                color: Theme.fg
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: outChip.outText
            }
            MouseArea { id: outTap; anchors.fill: parent; onClicked: Store.act("quick.toggle") }
            FocusRing { parent: outChip.face; anchors.fill: parent; shown: outChip.activeFocus; corner: Theme.rFull }
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
