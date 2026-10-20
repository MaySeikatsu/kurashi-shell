.pragma library

// Pure helpers of the lyrics views (docs/ux/lyrics.md "Fit"): the playing position from svc.media's reading, and the
// current line by binary search (DMS `LyricsController.qml` `indexFor`). No state.

// The position in ms now: svc.media's `position_us` read at `position_at_ms`, advanced at `rate` while playing (the
// media card's interpolation), shifted by the user's offset (positive = lines come earlier). NaN without a reading.
function positionMs(media, nowMs, offsetMs) {
    if (!media || typeof media.position_us !== "number" || typeof media.position_at_ms !== "number") return NaN
    var rate = typeof media.rate === "number" ? media.rate : 1
    var p = media.position_us / 1000
    if (media.playing === true) p += Math.max(0, nowMs - media.position_at_ms) * rate
    if (typeof media.length_us === "number" && media.length_us > 0) p = Math.min(p, media.length_us / 1000)
    return p + (offsetMs || 0)
}

// The index of the line sung at `ms`: the last line that starts at or before it; -1 before the first (or without lines).
function indexAt(lines, ms) {
    if (!lines || lines.length === 0 || isNaN(ms) || ms < lines[0].t_ms) return -1
    var lo = 0, hi = lines.length - 1
    while (lo < hi) {
        var mid = (lo + hi + 1) >> 1
        if (lines[mid].t_ms <= ms) lo = mid
        else hi = mid - 1
    }
    return lo
}

// Milliseconds of playback until the line after `idx` starts (Infinity when there is none).
function untilNext(lines, idx, ms) {
    var n = idx + 1
    if (!lines || n >= lines.length || isNaN(ms)) return Infinity
    return Math.max(0, lines[n].t_ms - ms)
}

// The track svc.media shows, as `lyrics.track` takes it ({} when nothing plays).
function trackOf(media) {
    if (!media || media.available === false) return {}
    var title = String(media.title || "").trim()
    if (title === "") return {}
    var t = { title: title, artist: String(media.artist || "").trim() }
    if (media.album) t.album = String(media.album).trim()
    if (typeof media.length_us === "number" && media.length_us > 0) t.length_us = media.length_us
    return t
}

// Whether the document's track is the one svc.media shows now (the document follows a track change a moment later).
function sameTrack(doc, track) {
    var d = doc && doc.track
    if (!d || !track.title) return false
    return d.title === track.title && (d.artist || "") === (track.artist || "")
}

function fill(s, vars) {
    return String(s).replace(/\{(\w+)\}/g, function (m, k) { return vars[k] !== undefined ? String(vars[k]) : m })
}
