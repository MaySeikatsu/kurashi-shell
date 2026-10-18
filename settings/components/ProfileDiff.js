.pragma library

// The lines of a profile review, counted the way the page counts them: a line changes a value when the value before and
// the value after differ. A line whose value stays the same only moves the setting to the profile (its layer changes),
// and the page lists it apart. The daemon decides what the review holds; this only compares its two values.

function valueDiffers(e) {
    return JSON.stringify(e.before ? e.before.value : null) !== JSON.stringify(e.after ? e.after.value : null)
}

function valueChanges(entries) {
    return (entries || []).filter(valueDiffers).length
}
