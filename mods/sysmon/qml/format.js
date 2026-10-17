// Numbers, units and names for the system monitor views. Words come from the i18n catalogue (rule 8); the daemon
// has already computed every value and level, so nothing here decides anything.
.pragma library

// A percentage as the bar and the tiles show it; "–" while there is no value.
function pct(v) {
    return (v === undefined || v === null) ? "–" : Math.round(v) + " %"
}

function temp(c) {
    return (c === undefined || c === null) ? "–" : Math.round(c) + " °C"
}

function load(v) {
    return (v === undefined || v === null) ? "–" : v.toFixed(2)
}

// Watts with one decimal, as a battery's draw is shown.
function watts(w) {
    return (w === undefined || w === null) ? "–" : w.toFixed(1) + " W"
}

// Bytes in binary units, labelled as such (GiB is what the kernel counts in).
function bytes(n) {
    if (n === undefined || n === null) return "–"
    var units = ["B", "KiB", "MiB", "GiB", "TiB"]
    var v = n
    var i = 0
    while (v >= 1024 && i < units.length - 1) {
        v /= 1024
        i++
    }
    return (v >= 10 || i === 0 ? Math.round(v) : v.toFixed(1)) + " " + units[i]
}

function rate(bps) {
    return bytes(bps) + "/s"
}

// A process name shortened to `max` characters with an ellipsis; the full name stays in the accessible name.
function name(s, max) {
    var t = String(s)
    return t.length > max ? t.slice(0, max - 1) + "…" : t
}

// `{name}` placeholders of a catalogue string.
function fill(template, subs) {
    var s = template
    for (var k in subs) s = s.split("{" + k + "}").join(String(subs[k]))
    return s
}
