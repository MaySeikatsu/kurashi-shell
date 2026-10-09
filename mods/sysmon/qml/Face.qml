import QtQuick
import "format.js" as F

// The Island's compact face for a sustained trouble (docs/ux/sysmon.md "Island face"): "CPU 95 % for 30 s · firefox".
// The daemon raises it only after the level stayed critical for the sustain window, and names the culprit.
Text {
    id: face
    required property var store
    required property var theme
    required property var i18n

    readonly property var s: store.docs["mod.sysmon"]
    readonly property var trouble: s !== undefined ? s.trouble : undefined

    text: trouble !== undefined ? face.line(trouble) : ""
    color: face.theme.fg
    font.pixelSize: face.theme.fsLabel
    font.family: face.theme.fam(text, face.theme.families)
    Accessible.role: Accessible.StaticText
    Accessible.name: text

    Component.onCompleted: store.watch("mod.sysmon")
    Component.onDestruction: store.unwatch("mod.sysmon")

    // "{kind} {value} for {secs} s", and "· {name}" when the daemon named a process.
    function line(t) {
        var kind = i18n.tr("sysmon.face.kind." + t.kind)
        var value = "–"
        if (t.kind === "cpu" && s.cpu !== undefined) value = F.pct(s.cpu.pct)
        if (t.kind === "mem" && s.mem !== undefined) value = F.pct(s.mem.pct)
        if (t.kind === "temp" && s.temp !== undefined) value = F.temp(s.temp.c)
        var out = F.fill(i18n.tr("sysmon.face.line"), {kind: kind, value: value, secs: t.since})
        if (t.culprit !== undefined) out += " " + F.fill(i18n.tr("sysmon.face.culprit"), {name: t.culprit.name})
        return out
    }
}
