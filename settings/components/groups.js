.pragma library
// Editing named groups (I502, W80; docs/ux/groups.md "Round two"): pure functions over a zone's (or a sidebar's) list and
// the `layout.groups` records. Each gesture returns {list, groups} — the whole new values — or null when it changes
// nothing; `ops` turns that into one `apply` (one transaction, one undo step). The list in Settings, its bar preview and
// the module menu use the same functions, so a drop, a key and a menu row write the same thing.

var PREFIX = "group:"

function isGroup(v) { return typeof v === "string" && v.indexOf(PREFIX) === 0 }
function idOf(v) { return String(v).slice(PREFIX.length) }
function entryOf(id) { return PREFIX + id }

// A record's members, in order (`members` is comma-separated, K38 records hold strings).
function membersOf(rec) {
    return String(rec && rec.members || "").split(",").map(function (s) { return s.trim() }).filter(function (s) { return s !== "" })
}
function find(groups, id) {
    for (var i = 0; i < groups.length; i++) if (groups[i].id === id) return i
    return -1
}
function recordOf(groups, id) {
    var i = find(groups, id)
    return i < 0 ? null : groups[i]
}
// The group `m` is a member of, among the groups this list names; "" when none.
function groupOf(list, groups, m) {
    for (var i = 0; i < list.length; i++) {
        if (!isGroup(list[i])) continue
        var rec = recordOf(groups, idOf(list[i]))
        if (rec && membersOf(rec).indexOf(m) >= 0) return rec.id
    }
    return ""
}
// The first free id `g<n>` (a slug, unique among the records).
function freeId(groups) {
    for (var n = 1; ; n++) if (find(groups, "g" + n) < 0) return "g" + n
}
function copy(groups) { return groups.map(function (g) { return Object.assign({}, g) }) }
function setMembers(groups, id, ms) {
    var i = find(groups, id)
    if (i >= 0) groups[i].members = ms.join(",")
}

// `m` out of wherever it stands in the list: the list itself, or a group's members (a group left empty goes, record and
// entry). Mutates both.
function takeOut(list, groups, m) {
    var at = list.indexOf(m)
    if (at >= 0) { list.splice(at, 1); return }
    var g = groupOf(list, groups, m)
    if (g === "") return
    var ms = membersOf(recordOf(groups, g)).filter(function (x) { return x !== m })
    if (ms.length > 0) setMembers(groups, g, ms)
    else dissolve(list, groups, g, [])
}
// Group `id` replaced in the list by `keep` (its members after an Ungroup, nothing when it emptied); its record goes.
function dissolve(list, groups, id, keep) {
    var at = list.indexOf(entryOf(id))
    if (at >= 0) Array.prototype.splice.apply(list, [at, 1].concat(keep))
    var i = find(groups, id)
    if (i >= 0) groups.splice(i, 1)
}

// `a` dropped onto `b` (both entries of the list, or a member onto an entry): a module onto a module makes a new group of
// both where `b` stood (in the list's order); onto a group, or a group onto a module, joins; a group onto a group merges
// (the caller confirms first).
function dropOnto(list, groups, a, b) {
    if (a === b || a === undefined || b === undefined) return null
    if (isGroup(a) && isGroup(b)) return merge(list, groups, idOf(a), idOf(b))
    if (isGroup(b)) return join(list, groups, a, idOf(b))
    if (isGroup(a)) return join(list, groups, b, idOf(a))
    // b may be a member of a group: a drop on a member joins its group.
    var bg = list.indexOf(b) < 0 ? groupOf(list, groups, b) : ""
    if (bg !== "") return join(list, groups, a, bg)
    var l = list.slice(), g = copy(groups)
    var ai = l.indexOf(a), bi = l.indexOf(b)
    var first = ai >= 0 && ai < bi ? a : b, second = first === a ? b : a
    takeOut(l, g, a)
    var at = l.indexOf(b)
    if (at < 0) return null
    var id = freeId(g)
    l.splice(at, 1, entryOf(id))
    g.push({ id: id, name: "", members: [first, second].join(","), accordion: false })
    return { list: l, groups: g }
}
// `m` joins group `id` at its end.
function join(list, groups, m, id) {
    var rec = recordOf(groups, id)
    if (!rec || membersOf(rec).indexOf(m) >= 0) return null
    var l = list.slice(), g = copy(groups)
    takeOut(l, g, m)
    if (find(g, id) < 0) return null
    setMembers(g, id, membersOf(recordOf(g, id)).concat([m]))
    return { list: l, groups: g }
}
// `m` leaves its group: it stands right after the group; the last member out dissolves the group.
function leave(list, groups, m) {
    var id = groupOf(list, groups, m)
    if (id === "") return null
    var l = list.slice(), g = copy(groups)
    var ms = membersOf(recordOf(g, id)).filter(function (x) { return x !== m })
    if (ms.length === 0) { dissolve(l, g, id, [m]); return { list: l, groups: g } }
    setMembers(g, id, ms)
    l.splice(l.indexOf(entryOf(id)) + 1, 0, m)
    return { list: l, groups: g }
}
// Group `id` dissolved: its members stand where it stood, in order.
function ungroup(list, groups, id) {
    var rec = recordOf(groups, id)
    if (!rec) return null
    var l = list.slice(), g = copy(groups)
    dissolve(l, g, id, membersOf(rec).filter(function (m) { return l.indexOf(m) < 0 }))
    return { list: l, groups: g }
}
// Group `from` merged into `into`: its members appended, its record and entry gone.
function merge(list, groups, from, into) {
    if (from === into) return null
    var a = recordOf(groups, from), b = recordOf(groups, into)
    if (!a || !b) return null
    var l = list.slice(), g = copy(groups)
    var ms = membersOf(b)
    membersOf(a).forEach(function (m) { if (ms.indexOf(m) < 0) ms.push(m) })
    setMembers(g, into, ms)
    dissolve(l, g, from, [])
    return { list: l, groups: g }
}
// One record's field changed (the group row's name or Accordion).
function setField(groups, id, field, value) {
    var g = copy(groups), i = find(g, id)
    if (i < 0) return null
    g[i][field] = value
    return g
}

// The apply ops of a result: the records (global) and the list (on `output` when the list is an output's own).
// A result without a list (a group's name or Accordion) writes the records only.
function ops(res, listKey, output) {
    var out = [{ set: "layout.groups", value: res.groups }]
    if (res.list === null) return out
    var l = { set: listKey, value: res.list }
    if (output) l.output = output
    out.push(l)
    return out
}
