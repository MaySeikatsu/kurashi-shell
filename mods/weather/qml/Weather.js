.pragma library
// Mapping and formatting for the weather views. The daemon decides what is in effect (tier, units,
// which values exist); these functions only turn its condition keys and ISO local times into text.

var GLYPH = {
    clear: "☀",
    mainly_clear: "☀",
    partly_cloudy: "⛅",
    overcast: "☁",
    fog: "≋",
    drizzle: "☂",
    freezing_drizzle: "☂",
    rain: "☔",
    freezing_rain: "☔",
    snow: "❄",
    snow_grains: "❄",
    showers: "☔",
    snow_showers: "❄",
    thunder: "⛈",
    thunder_hail: "⛈",
    unknown: "?"
};

// Glyph of a condition key; the night variant only for the clear sky.
function glyph(code, isDay) {
    if (isDay === false && (code === "clear" || code === "mainly_clear")) return "☾";
    return GLYPH[code] !== undefined ? GLYPH[code] : GLYPH.unknown;
}

// A value the daemon did not send is a dash, never a zero (Shōjiki).
function has(v) {
    return v !== undefined && v !== null && !isNaN(v);
}

function num(v) {
    return has(v) ? String(Math.round(v)) : "—";
}

function deg(v) {
    return has(v) ? Math.round(v) + "°" : "—";
}

// "2026-10-09T14:00" -> "14:00"; "" for anything else.
function hm(iso) {
    return iso && iso.length >= 16 ? iso.substring(11, 16) : "";
}

// "2026-10-09" (or a local ISO time) -> [year, month, day] as numbers, or null.
function ymd(iso) {
    if (!iso || iso.length < 10) return null;
    var y = parseInt(iso.substring(0, 4), 10);
    var m = parseInt(iso.substring(5, 7), 10);
    var d = parseInt(iso.substring(8, 10), 10);
    return isNaN(y) || isNaN(m) || isNaN(d) ? null : [y, m, d];
}

// UV index to its level key (the scale the Japanese and WHO tables use).
function uvLevel(uv) {
    if (!has(uv)) return "";
    if (uv < 3) return "low";
    if (uv < 6) return "moderate";
    if (uv < 8) return "high";
    if (uv < 11) return "very_high";
    return "extreme";
}

// The age text of a document age in seconds, from the frontend's I18n.tr (keys passed in).
function ageParts(ageS) {
    var s = Math.max(0, Math.floor(ageS || 0));
    if (s < 60) return { key: "mod-weather.age.now", n: 0 };
    if (s < 3600) return { key: "mod-weather.age.minutes", n: Math.floor(s / 60) };
    return { key: "mod-weather.age.hours", n: Math.floor(s / 3600) };
}

function fill(text, values) {
    var out = text;
    for (var k in values) out = out.split("{" + k + "}").join(String(values[k]));
    return out;
}

// Rain intensity key from the daemon ("light", "moderate", "heavy").
function intensityKey(k) {
    return k === "moderate" || k === "heavy" ? k : "light";
}
