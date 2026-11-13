// The appearance menu's pure helpers (W84, docs/ux/appearance-menu.md). No state: the menu and its hosts call these.
.pragma library

// The rail, in order. A pane's rows are the schema's (`appearance = "<pane>"` on a row, rule 3); this list only names
// the panes, their icons (in nix/icon-names.txt) and their i18n keys.
var panes = [
    { id: "wallpaper", icon: "wallpaper", glyph: "▦" },
    { id: "colours", icon: "palette", glyph: "◐" },
    { id: "style", icon: "style", glyph: "✦" },
    { id: "material", icon: "texture", glyph: "▤" },
    { id: "motion", icon: "animation", glyph: "≈" },
    { id: "effects", icon: "auto_awesome", glyph: "❖" },
    { id: "fonts", icon: "text_fields", glyph: "Aa" }
]

function indexOf(id) {
    for (var i = 0; i < panes.length; i++) if (panes[i].id === id) return i
    return -1
}
function paneOf(id) { var i = indexOf(id); return i >= 0 ? panes[i] : panes[0] }

// The schema rows a pane shows, in the schema's order: rows marked with the pane, not advanced.
function rowsOf(schema, pane) {
    var out = []
    if (!schema || !schema.pages) return out
    for (var i = 0; i < schema.pages.length; i++) {
        var p = schema.pages[i]
        for (var j = 0; j < p.sections.length; j++) {
            var rs = p.sections[j].rows
            for (var k = 0; k < rs.length; k++) {
                var r = rs[k]
                if (r.advanced === true) continue
                if ((r.appearance || []).indexOf(pane) >= 0) out.push(r)
            }
        }
    }
    return out
}
function rowOf(schema, key) {
    if (!schema || !schema.pages) return null
    for (var i = 0; i < schema.pages.length; i++)
        for (var j = 0; j < schema.pages[i].sections.length; j++) {
            var rs = schema.pages[i].sections[j].rows
            for (var k = 0; k < rs.length; k++) if (rs[k].key === key) return rs[k]
        }
    return null
}

// Values compare as JSON (lists and objects included).
function same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }

// ---- the launcher's rows (stand-in for CONTRACT-CHANGE row 790) ----------------------------------------------------
// Until the daemon offers `appearance:<pane>` rows itself, the launcher adds them here: the words of each pane
// (`appearance-menu.words.<pane>`, every language's words in its own catalogue) against the typed text. A word matches
// when it starts with the text (3 characters at least) or the text starts with it. At most three rows, first.
function launcherRows(q, tr) {
    var t = String(q || "").trim().toLowerCase()
    if (t.length < 3) return []
    var c = t.charAt(0)
    if (c === ":" || c === ";" || c === ">" || c === "?" || c === "/" || c === "!") return []
    var out = []
    for (var i = 0; i < panes.length && out.length < 3; i++) {
        var words = String(tr("appearance-menu.words." + panes[i].id)).toLowerCase().split(/[\s,、]+/)
        for (var j = 0; j < words.length; j++) {
            var w = words[j]
            if (w === "") continue
            if (w.indexOf(t) === 0 || (t.indexOf(w) === 0 && w.length >= 4)) {
                out.push({ kind: "appearance", id: "appearance:" + panes[i].id, icon: panes[i].icon,
                           name: tr("appearance-menu.pane." + panes[i].id),
                           generic: tr("appearance-menu.row.generic") })
                break
            }
        }
    }
    return out
}
