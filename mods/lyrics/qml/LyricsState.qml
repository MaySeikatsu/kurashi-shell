import QtQuick
import qs.core
import "Lyrics.js" as L

// What every lyrics view shares (docs/ux/lyrics.md "Fit"): it watches svc.media and mod.lyrics while `live`, tells the
// daemon the track svc.media shows (`lyrics.track`, the same track again is a no-op there), and maps the playing
// position to the current line. No per-second timer: one single-shot timer wakes at the next line's start, and only
// while `live`, synced lines are shown and the track plays (Ma). The document never changes while a song plays.
Item {
    id: st
    property bool live: true
    visible: false

    Watch { doc: "svc.media"; active: st.live }
    Watch { doc: "mod.lyrics"; active: st.live }

    readonly property var media: Store.docs["svc.media"] || ({})
    readonly property var d: Store.docs["mod.lyrics"] || ({})
    readonly property var cfg: (Store.docs["config"] && Store.docs["config"].values) || ({})
    readonly property int offsetMs: {
        var p = cfg["mods.lyrics.offset_ms"]
        return p && typeof p.value === "number" ? p.value : 0
    }
    readonly property bool barLine: {
        var p = cfg["mods.lyrics.bar_line"]
        return !(p && p.value === false)
    }

    readonly property var track: L.trackOf(media)
    readonly property string trackKey: JSON.stringify(track)
    readonly property bool hasTrack: track.title !== undefined
    readonly property bool playing: hasTrack && media.playing === true
    readonly property bool canSeek: !!(media.can && media.can.seek === true)
    // The document is about the track on screen (it follows a change a moment later: until then, "searching").
    readonly property bool fresh: hasTrack && L.sameTrack(d, track)
    // hidden · searching · synced · plain · instrumental · none · offline · error
    readonly property string phase: {
        if (!hasTrack) return "hidden"
        if (!fresh || d.state === "searching") return "searching"
        if (d.state === "ready") return d.synced === true ? "synced" : d.instrumental === true ? "instrumental" : "plain"
        if (d.state === "offline" || d.state === "error") return d.state
        return "none"
    }
    readonly property var lines: phase === "synced" ? (d.lines || []) : []
    readonly property string plain: phase === "plain" ? String(d.plain || "") : ""
    readonly property string reasonText: d.reason ? I18n.tr(d.reason) : ""

    property real nowMs: Date.now()
    readonly property real posMs: L.positionMs(media, nowMs, offsetMs)
    readonly property int index: L.indexAt(lines, posMs)
    readonly property string currentText: index >= 0 && index < lines.length ? lines[index].text : ""

    function send() {
        if (!st.live || !Store.live) return
        Store.act("lyrics.track", st.track)
    }
    function retry() { Store.act("lyrics.retry", {}) }
    // A click on a line: seek there, where the player allows it (svc.media `can.seek`).
    function seekTo(i) {
        if (!canSeek || i < 0 || i >= lines.length) return
        Store.act("media.set_position", { us: Math.max(0, Math.round((lines[i].t_ms - offsetMs) * 1000)) })
    }
    onTrackKeyChanged: send()
    onLiveChanged: send()
    Connections {
        target: Store
        function onLiveChanged() { st.send() }
    }
    Component.onCompleted: send()

    // The next line's start, re-armed on every reading and every line change.
    function arm() {
        wake.stop()
        if (!st.live || !st.playing || st.lines.length === 0 || isNaN(st.posMs)) return
        var rate = typeof media.rate === "number" && media.rate > 0 ? media.rate : 1
        var ms = L.untilNext(st.lines, st.index, st.posMs) / rate
        if (!isFinite(ms)) return
        wake.interval = Math.max(40, Math.min(ms + 15, 30000))
        wake.start()
    }
    onMediaChanged: { nowMs = Date.now(); arm() }
    onIndexChanged: arm()
    onLinesChanged: arm()
    onPlayingChanged: arm()
    Timer {
        id: wake
        repeat: false
        onTriggered: { st.nowMs = Date.now(); st.arm() }
    }
}
