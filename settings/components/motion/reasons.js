.pragma library
// The daemon's own reason on a motion row's provenance (K83: `config.diag.form.surface`, the resolved motion is off …)
// that Store.inertReasons does not word: those it knows (requires, a pending restart, an unavailable offer, a mod that is
// off, a forced layer) it lists itself. The daemon decides; this only finds the line to show (rule 1, K21). Result:
// {text: i18n key, key: the setting that controls it or ""} or null.
var KNOWN = ["settings.inert.requires", "settings.pending.restart", "settings.choice.unavailable", "mods.disabled"]

function extra(prov) {
    if (!prov || !prov.reason || prov.forced_by) return null
    if (KNOWN.indexOf(prov.reason) >= 0) return null
    return { text: prov.reason, key: prov.inert_by || "" }
}
