.pragma library

// Reads of the `mods` document (K26, K28), shared by ModLoader, Island, Bar and Stage. A mod entry's `qml`
// map names the file of each component it provides (`panel:x`, `widget:x`, `island-face:x`,
// `island-face:x:expanded`); only enabled native mods carry one (PROTOCOL §5). Pure functions, no state.

// The file URL of component `provide` of the mod `mod` (any mod when ""), or "" when no loaded mod has one.
function qmlOf(doc, provide, mod) {
    var list = (doc && doc.mods) || []
    for (var i = 0; i < list.length; i++) {
        var e = list[i]
        if (mod && e.id !== mod) continue
        var url = (e.qml || ({}))[provide]
        if (typeof url === "string" && url !== "") return url
    }
    return ""
}

// Every `widget:*` component of every enabled mod, in mod order: [{ mod, provide, url }].
function widgets(doc) {
    var out = []
    var list = (doc && doc.mods) || []
    for (var i = 0; i < list.length; i++) {
        var q = list[i].qml || ({})
        for (var key in q)
            if (key.indexOf("widget:") === 0) out.push({ mod: list[i].id, provide: key, url: q[key] })
    }
    return out
}

// Every `surface:*` component of every enabled mod, in mod order: [{ mod, provide, url }] (K38, row 88). The frontend
// creates one instance per output of each (shell.qml), with the output as its `screen`.
function surfaces(doc) {
    var out = []
    var list = (doc && doc.mods) || []
    for (var i = 0; i < list.length; i++) {
        var q = list[i].qml || ({})
        for (var key in q)
            if (key.indexOf("surface:") === 0) out.push({ mod: list[i].id, provide: key, url: q[key] })
    }
    return out
}

// `mod:<id>:<panel>` (runtime.ui.panel of a mod panel, K26) as { mod, panel }; null for any other panel.
function panelOf(panel) {
    var s = String(panel || "")
    if (s.indexOf("mod:") !== 0) return null
    var rest = s.substring(4)
    var c = rest.indexOf(":")
    if (c <= 0 || c === rest.length - 1) return null
    return { mod: rest.substring(0, c), panel: rest.substring(c + 1) }
}
