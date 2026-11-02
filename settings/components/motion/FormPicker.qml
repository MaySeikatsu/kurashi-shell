import QtQuick
import "../../core"
import ".."
import "reasons.js" as RS

// The form a surface opens or closes in (brief §5, §6, §8): a dropdown of the forms the daemon offers (`motion.forms`), with
// a small glyph of the form in effect. The forms meta (`motion.forms` token: {family, surfaces, available, …}, W59.1)
// filters it: a form not built yet (`available: false`) is left out, and on a surface's own row
// (theme.motion.form.<surface>.<dir>) a form whose `surfaces` do not list that surface is left out too — unless it is the
// value now, which stays (greyed, with why) so the dropdown never hides what is set; the daemon's reason for it shows under
// the dropdown. Until the meta is published every offer is open. The empty offer names what it follows ("As the default ·
// Fold"). A picker (SettingRow.picker) and the cells of the forms table: it reads and sets its own value.
Column {
    id: fp
    // Set by SettingRow, or by the forms table.
    property string rowKey: ""
    signal openKey(string key)
    spacing: 2

    readonly property var row: { Store.schema; var h = Store.rowOf(fp.rowKey); return h ? h.row : ({}) }
    // theme.motion.form.<dir> (every surface's default) or theme.motion.form.<surface>.<dir>.
    readonly property var parts: fp.rowKey.replace("theme.motion.form.", "").split(".")
    readonly property string surface: fp.parts.length === 2 ? fp.parts[0] : ""
    readonly property string dir: fp.parts[fp.parts.length - 1]
    readonly property var prov: { Store.config; return Store.prov(fp.rowKey, "") }
    readonly property string value: fp.prov && typeof fp.prov.value === "string" ? fp.prov.value : ""
    // The daemon's own reason (K83: a form that cannot serve this surface, motion off …), when Store.inertReasons does not
    // word it: shown here, and inert.
    readonly property var own: RS.extra(fp.prov)
    readonly property bool inert: { Store.config; return fp.own !== null || Store.inertReasons(fp.row, "").some(function (x) {
        return x.kind !== "pending" && x.kind !== "unavailable" && x.kind !== "mod_off" }) }
    readonly property bool editable: !fp.inert && Store.live

    readonly property var tokens: { Store.theme; return Store.theme.tokens || ({}) }
    // The forms meta (W59.1): {<form>: {family, surfaces, available, …}}, or {} until it is published.
    readonly property var meta: { var m = fp.tokens["motion.forms"]; return m && typeof m === "object" ? m : ({}) }
    function formName(id) {
        if (id === "" || id === undefined) return ""
        if (id === "none") return I18n.tr("motion.ui.form.none")
        return I18n.has("config.choice.motion.form." + id) ? I18n.tr("config.choice.motion.form." + id) : id
    }
    // What "" resolves to here: the surface's resolved form (token motion.form.<surface>.<dir>, W59.1), else the default
    // row's value, else the profile's form (today's motion.style).
    readonly property string follows: {
        Store.config
        if (fp.surface !== "") {
            var t = fp.tokens["motion.form." + fp.surface + "." + fp.dir]
            if (typeof t === "string" && t !== "") return t
            var d = Store.valueOf("theme.motion.form." + fp.dir, "")
            if (typeof d === "string" && d !== "") return d
        }
        var s = fp.tokens["motion.style"]
        return typeof s === "string" ? s : ""
    }
    readonly property string inEffect: fp.value !== "" ? fp.value : fp.follows
    function fits(id) {
        var m = fp.meta[id]
        if (!m) return true
        if (m.available === false) return false
        return fp.surface === "" || !Array.isArray(m.surfaces) || m.surfaces.indexOf(fp.surface) >= 0
    }
    readonly property var offers: {
        var tr = I18n.strings
        var list = fp.row.choices ?? []
        var out = []
        list.forEach(function (c) {
            if (c.value === "") {
                var what = fp.formName(fp.follows)
                var key = fp.surface === "" ? "motion.ui.form.follow_profile" : "motion.ui.form.follow_default"
                out.push({ value: "", label: what !== "" ? I18n.fmt(key + "_named", { form: what }) : I18n.tr(key) })
            } else if (fp.fits(c.value)) {
                out.push(c)
            } else if (c.value === fp.value) {
                out.push({ value: c.value, label: c.label, enabled: false, reason: "motion.ui.form.unfit" })
            }
        })
        return out
    }

    Row {
        width: parent.width
        spacing: Theme.gap
        FormGlyph {
            id: glyph
            anchors.verticalCenter: parent.verticalCenter
            form: fp.inEffect
            opacity: fp.editable ? 1 : 0.5
        }
        Select {
            objectName: "form:" + fp.rowKey
            width: Math.min(360, Math.max(160, fp.width - glyph.width - Theme.gap))
            label: fp.surface === "" ? I18n.tr(fp.row.label ?? "")
                : I18n.fmt("motion.ui.form.cell_name", { surface: I18n.tr("motion.surface." + fp.surface),
                                                         dir: I18n.tr("motion.ui.form.dir." + fp.dir) })
            choices: fp.offers
            current: fp.value
            enabled: fp.editable
            cancellable: false
            onPicked: v => { if (v !== fp.value) Store.setValue(fp.rowKey, v, "") }
        }
    }
    MotionReason { reason: fp.own; onOpenKey: key => fp.openKey(key) }
}
