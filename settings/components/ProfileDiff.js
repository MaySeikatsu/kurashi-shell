.pragma library

// The lines of a profile review (PROTOCOL §6). A line whose value stays the same carries `same_value: true` (I64): it only
// moves the setting to the profile, and the page lists it apart. The page does not compare values itself; the daemon says
// which lines change a value.

function changesValue(e) {
    return !e.same_value
}

function sameValue(e) {
    return !!e.same_value
}

function valueChanges(entries) {
    return (entries || []).filter(changesValue).length
}
