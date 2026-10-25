.pragma library
// W36 (I102, docs/ux/window-list.md): the app behind a window and its icon, one chain for the bar's window list and the
// dock — never a blank tile. Quickshell's objects are passed in (a library script sees no QML singletons).

// The desktop entry of a window's app id: Quickshell's heuristic (id, then lower case), then an entry whose
// StartupWMClass is the app id (case-insensitive: X11 classes and some Wayland app ids differ only in case); else null.
function entryFor(entries, appId) {
    var id = String(appId || "")
    if (id === "") return null
    var e = entries.heuristicLookup(id)
    if (e) return e
    var want = id.toLowerCase()
    var list = entries.applications ? entries.applications.values : []
    for (var i = 0; i < list.length; i++) {
        var c = list[i].startupClass
        if (c && String(c).toLowerCase() === want) return list[i]
    }
    return null
}

// The icon's path: the entry's icon, else an icon named after the app id (as is, lower case, the last part of a
// reverse-DNS id: `org.gnome.Nautilus` → `nautilus`); "" when the icon theme has none (the caller draws a letter).
function iconSource(qs, entry, appId) {
    if (entry && entry.icon) {
        var p = qs.iconPath(entry.icon, true)
        if (p !== "") return p
    }
    var id = String(appId || "")
    if (id === "") return ""
    var names = [id, id.toLowerCase()]
    var dot = id.lastIndexOf(".")
    if (dot >= 0 && dot < id.length - 1) names.push(id.substring(dot + 1).toLowerCase())
    for (var i = 0; i < names.length; i++) {
        var q = qs.iconPath(names[i], true)
        if (q !== "") return q
    }
    return ""
}

// The letter for a tile without an icon: the entry's name, else the app id's last part (`net.example.NoEntry` → N).
function letterOf(entry, appId) {
    var named = !!(entry && entry.name)
    var s = named ? String(entry.name) : String(appId || "")
    var dot = s.lastIndexOf(".")
    if (!named && dot >= 0 && dot < s.length - 1) s = s.substring(dot + 1)
    return s.charAt(0).toUpperCase()
}
