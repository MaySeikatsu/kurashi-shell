.pragma library

// One allocation per bar row (B48, docs/ux/bar-fit.md): the start, centre and end zones of a top or bottom bar laid out
// together, so no module is ever drawn over another. A pure function of what the modules say (their full, compact and
// minimum widths) and the bar's width; Bar.qml applies its answer on the next turn and writes only what changed.
//
// spec = { width, margin, gap, overflowW, zones: { start: Z, center: Z, end: Z } }
//   Z = { runGap, runs: [ { pieceGap, pieces: [ { hostGap, hosts: [H] } ] } ] }  — the ZoneRow's own nesting and gaps
//   H = { key, id, full, compact, min, elastic, snap? }  — present modules only; `compact` = `full` without a compact
//       form; `snap(px)`: the width an elastic module that draws in steps takes in that room (≤ px)
// → { levels: {key: 0 full | 1 compact | 2 in the overflow}, rooms: {key: px} (elastic), widths: {start, center, end},
//     centerX (the centre's left edge, in the row's coordinates), parked: {start, center, end} (counts), fits }

// The anchors at the bar's ends go into the overflow last, the island never (the brief's priority rule).
var ANCHORS = ["launcher", "workspaces", "sidebar_left", "sidebar_right", "quick", "clock"]

function zoneWidth(z, wOf, parkedN, overflowW) {
    var total = 0, runs = 0
    for (var i = 0; i < z.runs.length; i++) {
        var run = z.runs[i], rw = 0, pieces = 0
        for (var j = 0; j < run.pieces.length; j++) {
            var piece = run.pieces[j], pw = 0, hosts = 0
            for (var k = 0; k < piece.hosts.length; k++) {
                var w = wOf(piece.hosts[k])
                // (a positioner skips what is hidden or has no width: no gap for it)
                if (w <= 0) continue
                pw += (hosts > 0 ? piece.hostGap : 0) + w
                hosts++
            }
            if (hosts === 0) continue
            rw += (pieces > 0 ? run.pieceGap : 0) + pw
            pieces++
        }
        if (pieces === 0) continue
        total += (runs > 0 ? z.runGap : 0) + rw
        runs++
    }
    if (parkedN > 0) total += (runs > 0 ? z.runGap : 0) + overflowW
    return total
}

function hostsOf(z) {
    var out = []
    for (var i = 0; i < z.runs.length; i++)
        for (var j = 0; j < z.runs[i].pieces.length; j++)
            for (var k = 0; k < z.runs[i].pieces[j].hosts.length; k++) out.push(z.runs[i].pieces[j].hosts[k])
    return out
}

// The level t at which sum(clamp(t, lo_i, hi_i)) is `target` (water filling): each item's share is clamp(t, lo, hi).
function levelFor(items, target) {
    var lo = 0, hi = 0
    for (var i = 0; i < items.length; i++) hi = Math.max(hi, items[i].hi)
    for (var n = 0; n < 40; n++) {
        var mid = (lo + hi) / 2, s = 0
        for (var k = 0; k < items.length; k++) s += Math.max(items[k].lo, Math.min(items[k].hi, mid))
        if (s > target) hi = mid
        else lo = mid
    }
    return lo
}

function allocate(spec) {
    var names = ["start", "center", "end"]
    var Z = spec.zones
    var level = {}, all = {}, zoneOf = {}
    for (var zi = 0; zi < 3; zi++) {
        var hs = hostsOf(Z[names[zi]])
        for (var i = 0; i < hs.length; i++) { level[hs[i].key] = 0; all[hs[i].key] = hs[i]; zoneOf[hs[i].key] = names[zi] }
    }
    var parked = { start: 0, center: 0, end: 0 }
    var inner = W0()
    function W0() { return Math.max(0, spec.width - 2 * spec.margin) }
    function minOf(h) {
        var l = level[h.key]
        if (l === 2) return 0
        if (h.elastic) return h.min
        return l === 1 ? h.compact : h.full
    }
    function widthOf(name, wOf) { return zoneWidth(Z[name], wOf, parked[name], spec.overflowW) }
    function gapsOf(w) {
        var n = (w.start > 0 ? 1 : 0) + (w.center > 0 ? 1 : 0) + (w.end > 0 ? 1 : 0)
        return Math.max(0, n - 1) * spec.gap
    }
    function mins() { return { start: widthOf("start", minOf), center: widthOf("center", minOf), end: widthOf("end", minOf) } }
    // The order a zone gives way in: from its inner end (the module nearest the centre) outwards; the centre from its end.
    function order(name) {
        var hs = hostsOf(Z[name])
        return name === "end" ? hs : hs.slice().reverse()
    }
    function nextStep(name) {
        var hs = order(name), k
        for (k = 0; k < hs.length; k++)
            if (level[hs[k].key] === 0 && !hs[k].elastic && hs[k].compact < hs[k].full - 0.5) return [hs[k], 1]
        for (k = 0; k < hs.length; k++)
            if (level[hs[k].key] !== 2 && ANCHORS.indexOf(hs[k].id) < 0 && hs[k].id !== "island") return [hs[k], 2]
        for (k = 0; k < hs.length; k++)
            if (level[hs[k].key] !== 2 && hs[k].id !== "island") return [hs[k], 2]
        return null
    }

    var m = mins(), fits = false
    for (var guard = 0; guard < 200; guard++) {
        if (m.start + m.center + m.end + gapsOf(m) <= inner) { fits = true; break }
        // The crowded side: the one past its budget, a side's spare going to the other (the centre's room taken first).
        var avail = inner - m.center - gapsOf(m)
        var overS = m.start - Math.max(avail / 2, avail - m.end)
        var overE = m.end - Math.max(avail / 2, avail - m.start)
        var tries = overS > 0 || overE > 0 ? (overS >= overE ? ["start", "end", "center"] : ["end", "start", "center"])
            : ["center", "start", "end"]
        var step = null
        for (var t = 0; t < tries.length && !step; t++) step = nextStep(tries[t])
        if (!step) break
        if (step[1] === 2) parked[zoneOf[step[0].key]]++
        level[step[0].key] = step[1]
        m = mins()
    }

    // What is left goes to the elastic modules, the smaller wants first.
    var rooms = {}, el = []
    for (var key in all) {
        var h = all[key]
        if (h.elastic && level[key] !== 2) el.push({ key: key, lo: h.min, hi: Math.max(h.min, h.full) })
    }
    var extra = Math.max(0, inner - (m.start + m.center + m.end + gapsOf(m)))
    var sumLo = 0, sumHi = 0
    for (var e = 0; e < el.length; e++) { sumLo += el[e].lo; sumHi += el[e].hi }
    var lvl = levelFor(el, Math.min(sumHi, sumLo + extra))
    for (e = 0; e < el.length; e++) rooms[el[e].key] = Math.floor(Math.max(el[e].lo, Math.min(el[e].hi, lvl)))
    function finalOf(hh) {
        var l = level[hh.key]
        if (l === 2) return 0
        if (hh.elastic) return rooms[hh.key]
        return l === 1 ? hh.compact : hh.full
    }
    var w = { start: widthOf("start", finalOf), center: widthOf("center", finalOf), end: widthOf("end", finalOf) }

    // The centre keeps the bar's middle: a side that reaches it trims its own elastic modules first (to their minimum),
    // then the centre moves away from it by the least amount.
    var mid = spec.width / 2
    if (w.center > 0) {
        var sides = ["start", "end"]
        for (var si = 0; si < 2; si++) {
            var name = sides[si]
            if (w[name] <= 0) continue
            var limit = mid - w.center / 2 - spec.gap - spec.margin
            var over = w[name] - limit
            if (over <= 0) continue
            var mine = [], cur = 0, low = 0
            for (e = 0; e < el.length; e++) if (zoneOf[el[e].key] === name) {
                mine.push({ key: el[e].key, lo: el[e].lo, hi: rooms[el[e].key] })
                cur += rooms[el[e].key]; low += el[e].lo
            }
            if (mine.length === 0) continue
            var cut = Math.min(over, cur - low)
            if (cut <= 0) continue
            var lv = levelFor(mine, cur - cut)
            for (var q = 0; q < mine.length; q++) rooms[mine[q].key] = Math.floor(Math.max(mine[q].lo, Math.min(mine[q].hi, lv)))
            w[name] = widthOf(name, finalOf)
        }
    }
    // An elastic module that draws in steps (the window list: whole buttons) takes the step its room holds, so the zone
    // is as wide as it will draw and the centre's place is exact.
    var snapped = false
    for (e = 0; e < el.length; e++) {
        var hs = all[el[e].key]
        if (!hs.snap) continue
        var sn = Math.min(rooms[el[e].key], Math.max(0, Math.floor(hs.snap(rooms[el[e].key]))))
        if (sn !== rooms[el[e].key]) { rooms[el[e].key] = sn; snapped = true }
    }
    if (snapped) w = { start: widthOf("start", finalOf), center: widthOf("center", finalOf), end: widthOf("end", finalOf) }
    var cx = -1
    if (w.center > 0) {
        var lo = spec.margin + (w.start > 0 ? w.start + spec.gap : 0)
        var hi = spec.width - spec.margin - (w.end > 0 ? w.end + spec.gap : 0) - w.center
        cx = Math.round(Math.max(lo, Math.min(hi, mid - w.center / 2)))
    }
    return { levels: level, rooms: rooms, widths: w, centerX: cx, parked: parked, fits: fits }
}
