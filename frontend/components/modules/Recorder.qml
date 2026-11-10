import QtQuick
import "../../core"
import "../quick"

// Module `recorder` (K47; W71 f, I475 6, docs/ux/control-centre-modules.md "The recorder"): a button on the bar, always
// (it was there only while a recording ran). Idle: the record mark; a click (or a hover, as `bar.hover` says) opens the
// recorder's card, the recorder page of the control centre (start, which screen, the sound, where the file goes, the last
// recording). Recording: a red mark and the running time; a click stops it (the obvious thing then, as GNOME's top-bar
// indicator and macOS's Stop key). `quick.click.recorder = switch`: an idle click starts recording at once. Without a
// recorder program it is the dim mark, inert, and says why (its accessible name, its card). Bar fit: the time is its
// value (compact: the mark alone); in a column the mark.
ControlModule {
    id: m
    RecordControl { id: c; live: m.live }
    ctl: c
    // (one name either way: swapping it while the icon settles its font loops, B70; the error colour says it records)
    glanceIcon: "screen_record"
    glanceGlyph: "●"
    alert: c.recording
    valueText: c.recording ? c.elapsed : ""
}
