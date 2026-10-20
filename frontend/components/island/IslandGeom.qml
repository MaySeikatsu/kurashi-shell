pragma Singleton
import QtQuick
import Quickshell

// Where each output's island pill rests, and which output's pill the Stage has taken (W21 morph). The Islands report
// their pill (`report`, only on a change); the Stage reads it to start its one shape at the pill's exact rect and to fold
// back into it, and names the output while its shape is out (`takenOn`), so that output's bar hides its pill: one
// island on screen, never two. Plain state, no timers (Ma).
Singleton {
    // { "<output>": { w, h, dx, face } }: the pill's width and face height (without the keycap shadow), the offset of its
    // centre from the bar's centre (the secondary glyph and "+N" beside it push it left), and the face it shows.
    property var pills: ({})
    function report(output, w, h, dx, face) {
        if (output === "") return
        var p = pills[output]
        if (p && p.w === w && p.h === h && p.dx === dx && p.face === face) return
        var n = Object.assign({}, pills)
        n[output] = { w: w, h: h, dx: dx, face: face }
        pills = n
    }
    function pillOf(output) { return pills[output] || null }
    // The output whose pill is inside the Stage's shape right now; "" when none.
    property string takenOn: ""
}
