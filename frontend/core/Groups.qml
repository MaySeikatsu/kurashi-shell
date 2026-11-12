pragma Singleton
import QtQuick
import Quickshell

// Named groups (session 30, I502, docs/ux/groups.md; `layout.groups`): `[[layout.groups]]` rows `{id, name, members,
// accordion}`, members comma-separated. A bar zone's list is expanded by the daemon (runtime.layout tags each member with
// its group); a sidebar's sections are expanded here, from the config document the shell already holds.
Singleton {
    readonly property var rows: {
        var v = ((Store.docs["config"] || ({})).values || ({}))["layout.groups"]
        return v && Array.isArray(v.value) ? v.value : []
    }
    // `group:<id>` as {id, name, members, accordion}, or null (not a group, or no such group).
    function of(token) {
        var s = String(token || "")
        if (s.indexOf("group:") !== 0) return null
        var id = s.substring(6)
        for (var i = 0; i < rows.length; i++) {
            var r = rows[i]
            if (r && r.id === id) return {
                id: id,
                name: String(r.name || "") !== "" ? String(r.name) : id,
                members: String(r.members || "").split(",").map(function (m) { return m.trim() })
                    .filter(function (m) { return m !== "" && m.indexOf("group:") !== 0 }),
                accordion: r.accordion === true
            }
        }
        return null
    }
}
