import QtQuick
import "format.js" as F

// The Island's compact face for a sustained trouble (docs/ux/sysmon.md "Island face"): "CPU 95 % for 30 s · firefox".
// The daemon raises it only after the level stayed critical for the sustain window, and names the culprit. The name
// is shortened on the face (the full name is in the accessible name and in the expanded view).
Text {
    id: face
    required property var store
    required property var theme
    required property var i18n

    readonly property var s: store.docs["mod.sysmon"]
    readonly property var trouble: s !== undefined ? s.trouble : undefined

    text: trouble !== undefined ? face.line(trouble, 18) : ""
    color: face.theme.fg
    elide: Text.ElideRight
    font.pixelSize: face.theme.fsLabel
    font.family: face.theme.fam(text, face.theme.families)
    font.features: ({"tnum": 1})
    Accessible.role: Accessible.StaticText
    Accessible.name: trouble !== undefined ? face.line(trouble, 200) : ""

    Component.onCompleted: store.watch("mod.sysmon")
    Component.onDestruction: store.unwatch("mod.sysmon")

    function value(t) {
        if (t.kind === "cpu" && s.cpu !== undefined) return F.pct(s.cpu.pct)
        if (t.kind === "mem" && s.mem !== undefined) return F.pct(s.mem.pct)
        if (t.kind === "temp" && s.temp !== undefined) return F.temp(s.temp.c)
        return "–"
    }

    // "{kind} {value} for {secs} s", and "· {name}" when the daemon named a process (shortened to `max` characters).
    function line(t, max) {
        var kind = i18n.tr("sysmon.face.kind." + t.kind)
        var out = F.fill(i18n.tr("sysmon.face.line"), {kind: kind, value: value(t), secs: t.since})
        if (t.culprit !== undefined) out += " " + F.fill(i18n.tr("sysmon.face.culprit"), {name: F.name(t.culprit.name, max)})
        return out
    }
}
