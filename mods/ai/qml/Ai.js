.pragma library

// Shared reads of the `mod.ai` document for the panel (docs/ux/ai.md). Pure functions over what the daemon sent.

// "{provider} at {url}" with the values of `args`.
function fill(s, args) {
    return String(s).replace(/\{(\w+)\}/g, function (m, k) { return args[k] !== undefined ? String(args[k]) : m })
}

// The provider's name: the label of its setting choice.
function providerLabel(tr, id) {
    return tr("mods.ai.provider." + (id || "ollama"))
}

// "Ollama · llama3.2:latest", "OpenAI · choose a model".
function chipText(tr, p) {
    if (!p) return ""
    var m = p.model ? p.model : tr(p.id === "ollama" ? "mod-ai.model.auto" : "mod-ai.model.none")
    return providerLabel(tr, p.id) + " · " + m
}

// The sentence of an error key, with the provider's address, name and key source filled in.
function errorText(tr, key, p, detail) {
    return fill(tr(key), { url: (p && p.url) || "", provider: providerLabel(tr, p && p.id), key: detail || (p && p.key) || "" })
}

// An answer's error shows its detail on its own line unless the sentence already names it (the key source).
function detailShown(key, detail) {
    return !!detail && key !== "mod-ai.error.no_key"
}

// A day as the history list shows it: the time for today, else the date.
function when(sec) {
    if (!sec) return ""
    var d = new Date(sec * 1000), now = new Date()
    if (d.toDateString() === now.toDateString())
        return ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2)
    return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2)
}
