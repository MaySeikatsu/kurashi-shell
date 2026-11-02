import QtQuick
import "../../core"
import ".."
import "reasons.js" as RS

// Forms per surface (brief §6, §8 "Surface | Opens | Closes"): one line per surface class with its two form pickers. Each
// cell is its own setting (theme.motion.form.<surface>.<dir>): a cell the user set says so, with its Reset; a line's
// reasons (why a cell is inert) sit under it, each once, with the link to the setting that controls it. The island leads
// with "Follows the default" (theme.motion.form.island.follow, K83 D3): while it is on, its own pickers are inert, say so,
// and show the form they follow.
Column {
    id: ft
    signal openKey(string key)
    objectName: "forms-table"
    spacing: 0

    readonly property var surfaces: ["island", "panel", "peek", "launcher", "centre", "toast", "sidebar", "dock", "bar",
                                     "osd", "menu", "dialog"]
    readonly property real nameW: Math.min(200, Math.max(120, width * 0.24))
    // Cells as wide as a dropdown wants (a wide window leaves the rest empty, not a gap between the columns).
    readonly property real cellW: Math.min(400, (width - nameW - 2 * Theme.gap) / 2)

    // The heading line.
    Row {
        spacing: Theme.gap
        height: Theme.controlH
        MotionText { width: ft.nameW; anchors.verticalCenter: parent.verticalCenter; small: true; color: Theme.dim; text: I18n.tr("motion.ui.forms.surface") }
        MotionText { width: ft.cellW; anchors.verticalCenter: parent.verticalCenter; small: true; color: Theme.dim; text: I18n.tr("motion.ui.forms.opens") }
        MotionText { width: ft.cellW; anchors.verticalCenter: parent.verticalCenter; small: true; color: Theme.dim; text: I18n.tr("motion.ui.forms.closes") }
    }

    Repeater {
        model: ft.surfaces
        delegate: Column {
            id: line
            required property string modelData
            required property int index
            readonly property string openKey: "theme.motion.form." + modelData + ".open"
            readonly property string closeKey: "theme.motion.form." + modelData + ".close"
            readonly property bool island: modelData === "island"
            readonly property var keys: island ? ["theme.motion.form.island.follow", openKey, closeKey] : [openKey, closeKey]
            // Each reason once (both cells usually share theirs).
            readonly property var reasons: {
                Store.config; Store.schema
                var seen = {}, out = []
                ;line.keys.forEach(function (k) {
                    var h = Store.rowOf(k)
                    if (!h) return
                    Store.inertReasons(h.row, "").forEach(function (r) {
                        if (seen[r.text]) return
                        seen[r.text] = true
                        out.push(r)
                    })
                    // The switch's own daemon reason (the cells show theirs under their dropdowns).
                    var own = k === "theme.motion.form.island.follow" ? RS.extra(Store.prov(k, "")) : null
                    if (own && !seen[own.text]) {
                        seen[own.text] = true
                        out.push({ kind: "daemon", key: own.key, text: I18n.tr(own.text) })
                    }
                })
                return out
            }
            function userSet(k) { Store.config; var p = Store.prov(k, ""); return !!p && !!p.source && p.source.kind === "user" }
            objectName: "forms-line:" + modelData
            width: ft.width
            spacing: Theme.gap / 2
            topPadding: Theme.gap / 2
            bottomPadding: Theme.gap / 2

            Rectangle { width: parent.width; height: 1; color: Theme.containerHigh }
            // The island's switch: it follows the default unless told not to.
            Loader {
                active: line.island
                visible: active
                width: parent.width
                sourceComponent: Row {
                    spacing: Theme.gap
                    readonly property var row: { Store.schema; var h = Store.rowOf("theme.motion.form.island.follow"); return h ? h.row : ({}) }
                    readonly property var prov: { Store.config; return Store.prov("theme.motion.form.island.follow", "") }
                    readonly property bool inert: { Store.config; return RS.extra(prov) !== null || Store.inertReasons(row, "").some(function (x) {
                        return x.kind !== "pending" && x.kind !== "unavailable" && x.kind !== "mod_off" }) }
                    MotionText { width: ft.nameW; anchors.verticalCenter: parent.verticalCenter; text: I18n.tr("motion.surface.island") }
                    Toggle {
                        objectName: "toggle:theme.motion.form.island.follow"
                        anchors.verticalCenter: parent.verticalCenter
                        label: I18n.tr("config.theme.motion.form.island.follow.label")
                        checked: parent.prov ? parent.prov.value === true : true
                        enabled: !parent.inert && Store.live
                        onToggled: v => Store.setValue("theme.motion.form.island.follow", v, "")
                    }
                    MotionText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: ft.width - ft.nameW - 60 - 2 * Theme.gap
                        small: true
                        color: Theme.dim
                        text: I18n.tr("motion.ui.forms.follow")
                    }
                }
            }
            Row {
                spacing: Theme.gap
                MotionText {
                    width: ft.nameW
                    anchors.verticalCenter: parent.verticalCenter
                    // The island's name is on its switch line; its pickers' line names what they are.
                    color: line.island ? Theme.dim : Theme.fg
                    small: line.island
                    text: line.island ? I18n.tr("motion.ui.forms.island_own") : I18n.tr("motion.surface." + line.modelData)
                }
                FormPicker { width: ft.cellW; rowKey: line.openKey; onOpenKey: key => ft.openKey(key) }
                FormPicker { width: ft.cellW; rowKey: line.closeKey; onOpenKey: key => ft.openKey(key) }
            }
            // A cell the user set: whose it is, and its Reset (the diff first, as every Reset).
            Row {
                visible: line.keys.some(function (k) { return line.userSet(k) })
                x: ft.nameW + Theme.gap
                spacing: Theme.gap
                Repeater {
                    model: line.keys
                    delegate: Row {
                        required property string modelData
                        visible: line.userSet(modelData)
                        spacing: Theme.gap / 2
                        // Which cell the chip is for: the line has up to three settings.
                        MotionText {
                            anchors.verticalCenter: parent.verticalCenter
                            small: true
                            color: Theme.dim
                            text: I18n.tr(/\.follow$/.test(parent.modelData) ? "motion.ui.forms.follow"
                                : /\.open$/.test(parent.modelData) ? "motion.ui.forms.opens" : "motion.ui.forms.closes") + ":"
                        }
                        ProvenanceChip { prov: { Store.config; return Store.prov(parent.modelData, "") ?? ({}) } key: parent.modelData }
                        ResetFlow {
                            ops: [Store.resetOp(parent.modelData, "")]
                            enabled: Store.live
                            tag: parent.modelData
                            width: 200
                        }
                    }
                }
            }
            Repeater {
                model: line.reasons
                delegate: Row {
                    required property var modelData
                    x: ft.nameW + Theme.gap
                    spacing: Theme.gap
                    MotionText {
                        width: Math.min(implicitWidth, ft.width - ft.nameW - 2 * Theme.gap - 80)
                        small: true
                        color: Theme.dim
                        text: (modelData.kind === "pending" ? "↻ " : "⊘ ") + modelData.text
                    }
                    LinkText {
                        visible: !!modelData.key
                        text: I18n.tr("settings.ui.open")
                        onActivated: ft.openKey(modelData.key)
                    }
                }
            }
        }
    }
}
