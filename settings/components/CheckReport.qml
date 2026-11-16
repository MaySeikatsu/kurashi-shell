import QtQuick
import "../core"

// The mod check's verdict (kurashi_mods::check; PROTOCOL §6 "The Mod Editor's four"), as the Mod Editor and the Mods page
// show it: the summary ("Every rule is met · 1 note"), then one line per rule of the report's `rules` — met or not, by its
// mark and in words, with each finding's `at` and `detail` under it. The list has role and state (not colour alone).
// `compact` (a Mods row) lists only the rules that have a finding.
Column {
    id: cr
    property var report: null
    property bool compact: false
    property string summaryName: ""
    spacing: Theme.gap / 2

    readonly property int errors: report ? (report.errors || 0) : 0
    readonly property int notes: report ? (report.notes || 0) : 0
    // [{rule, met, findings}], the rules not met first; a finding whose rule the list does not name still shows.
    readonly property var lines: {
        if (!report) return []
        var findings = report.findings || []
        var rules = (report.rules || []).slice()
        findings.forEach(function (f) { if (rules.indexOf(f.rule) < 0) rules.push(f.rule) })
        var out = rules.map(function (rule) {
            var own = findings.filter(function (f) { return f.rule === rule })
            return { rule: rule, met: !own.some(function (f) { return f.level === "error" }), findings: own }
        })
        if (compact) out = out.filter(function (l) { return l.findings.length > 0 })
        return out.filter(function (l) { return !l.met }).concat(out.filter(function (l) { return l.met }))
    }
    // The summary in words: what the editor's Create says too.
    readonly property string summary: !report ? ""
        : (errors === 0 ? I18n.tr("mods.new.check.passed")
           : errors === 1 ? I18n.tr("mods.new.check.failed_one") : I18n.fmt("mods.new.check.failed", { n: errors }))
          + (notes === 1 ? " · " + I18n.tr("mods.new.check.notes_one")
             : notes > 1 ? " · " + I18n.fmt("mods.new.check.notes", { n: notes }) : "")

    Row {
        width: cr.width
        spacing: Theme.gap
        Icon {
            id: verdict
            name: cr.errors > 0 ? "error" : "task_alt"
            filled: cr.errors > 0
            size: Theme.fs + 2
            color: cr.errors > 0 ? Theme.error : Theme.accent
        }
        Label {
            objectName: cr.summaryName
            width: cr.width - verdict.width - Theme.gap
            wrapMode: Text.WordWrap
            font.weight: Theme.wMedium
            color: cr.errors > 0 ? Theme.error : Theme.fg
            text: cr.summary
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
    }
    Column {
        visible: cr.lines.length > 0
        width: cr.width
        spacing: 2
        Accessible.role: Accessible.List
        Accessible.name: I18n.tr("mods.new.check")
        Repeater {
            model: cr.lines
            delegate: Item {
                id: line
                required property var modelData
                width: cr.width
                height: lineCol.implicitHeight + 4
                Accessible.role: Accessible.ListItem
                Accessible.name: lineLabel.text + (line.modelData.met ? ", " + I18n.tr("mods.new.check.met") : "")
                Icon {
                    id: mark
                    y: 1
                    name: line.modelData.met ? "check_circle" : "error"
                    filled: !line.modelData.met
                    size: Theme.fs + 1
                    color: line.modelData.met ? Theme.dim : Theme.error
                }
                Column {
                    id: lineCol
                    anchors.left: mark.right
                    anchors.leftMargin: Theme.gap
                    anchors.right: parent.right
                    Label {
                        id: lineLabel
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: line.modelData.met ? Theme.dim : Theme.fg
                        font.pixelSize: Theme.fs - 1
                        // (a met line says so by its mark and its name; a line not met in words too)
                        text: (I18n.has("mods.check." + line.modelData.rule) ? I18n.tr("mods.check." + line.modelData.rule)
                               : line.modelData.rule)
                              + (line.modelData.met ? "" : " · " + I18n.tr("mods.new.check.not_met"))
                    }
                    Repeater {
                        model: line.modelData.findings
                        Label {
                            required property var modelData
                            width: lineCol.width
                            wrapMode: Text.WordWrap
                            font.pixelSize: Theme.fs - 2
                            color: modelData.level === "error" ? Theme.error : Theme.dim
                            text: (modelData.level === "error" ? "✕ " : "· ") + modelData.at + " — " + modelData.detail
                        }
                    }
                }
            }
        }
    }
}
