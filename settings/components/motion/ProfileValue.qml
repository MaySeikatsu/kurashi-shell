import QtQuick
import "../../core"
import ".."

// A number whose lowest value means "the profile's" (K83: `squash`, `jelly`, `stagger_ms` at -1, `timing.<role>_ms` at 0),
// never shown as that raw number (Shōjiki). A switch "From the profile (0.40)" names what the profile gives; the slider sits
// there, faint, and moving it sets an own value from the first real one up. Switching back, as Reset, returns to the
// profile's. The profile's value is the daemon's: `motion.accent.<key>`, or for a duration the role's
// `motion.profile_curve.<role>.ms` (the profile alone, without the user's).
Column {
    id: pv
    property string rowKey: ""
    signal openKey(string key)
    spacing: Theme.gap / 2

    readonly property var row: { Store.schema; var h = Store.rowOf(pv.rowKey); return h ? h.row : ({}) }
    readonly property var prov: { Store.config; return Store.prov(pv.rowKey, "") }
    // The schema's default is the sentinel on every row this control serves.
    readonly property real sentinel: Number(pv.row.default ?? 0)
    readonly property real value: pv.prov && typeof pv.prov.value === "number" ? pv.prov.value : pv.sentinel
    readonly property bool follows: pv.value === pv.sentinel
    readonly property bool isInt: pv.row.type === "int" || (pv.row.unit ?? "") === "ms"
    // The first own value: 0 above a -1 sentinel, one step above a 0 one.
    readonly property real ownMin: pv.sentinel < 0 ? 0 : pv.sentinel + (pv.row.step || 1)
    readonly property real ownMax: Number(pv.row.max ?? 1)
    readonly property bool inert: { Store.config; return Store.inertReasons(pv.row, "").some(function (x) {
        return x.kind !== "pending" && x.kind !== "unavailable" && x.kind !== "mod_off" }) }
    readonly property bool editable: !pv.inert && Store.live

    // What the profile gives, from the theme document; NaN when it gives no number (a spring_q's duration is its spring's).
    readonly property real profiles: {
        Store.theme
        var t = Store.theme.tokens || ({})
        var m = /^theme\.motion\.timing\.([a-z]+)_ms$/.exec(pv.rowKey)
        if (m) {
            var c = t["motion.profile_curve." + m[1]]
            if (c && typeof c === "object") return c.ms > 0 ? c.ms : NaN
            var ms = t["motion.timed." + m[1] + "_ms"]
            return typeof ms === "number" && ms > 0 ? ms : NaN
        }
        var v = t["motion.accent." + pv.rowKey.replace("theme.motion.", "")]
        return typeof v === "number" ? v : NaN
    }
    function shown(v) {
        if (isNaN(v)) return ""
        var u = pv.row.unit ?? ""
        var n = pv.isInt ? String(Math.round(v)) : Number(v).toFixed(2)
        return u !== "" ? n + " " + u : n
    }
    function clamp(v) { return Math.max(pv.ownMin, Math.min(pv.ownMax, v)) }

    function follow(on) {
        if (!pv.editable) return
        if (on) Store.reset(pv.rowKey, "")
        else Store.setValue(pv.rowKey, pv.clamp(isNaN(pv.profiles) ? pv.ownMin : pv.profiles), "")
    }

    Row {
        spacing: Theme.gap
        Toggle {
            objectName: "inherit:" + pv.rowKey
            anchors.verticalCenter: parent.verticalCenter
            label: I18n.tr("motion.ui.inherit")
            checked: pv.follows
            enabled: pv.editable
            onToggled: v => pv.follow(v)
        }
        MotionText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, pv.width - 60)
            color: pv.follows ? Theme.fg : Theme.dim
            text: isNaN(pv.profiles) ? I18n.tr("motion.ui.inherit")
                : I18n.fmt("motion.ui.inherit.value", { value: pv.shown(pv.profiles) })
        }
        // The settings test reads whether the row follows the profile.
        Item { objectName: "inherit-on:" + pv.rowKey; visible: pv.follows; width: 0; height: 0 }
    }
    Slider {
        objectName: "slider:" + pv.rowKey
        width: Math.min(pv.width, 360)
        label: I18n.tr(pv.row.label ?? "")
        // At the profile's value while it follows (faint), else the own one.
        value: pv.follows ? pv.clamp(isNaN(pv.profiles) ? pv.ownMin : pv.profiles) : pv.value
        opacity: pv.follows ? 0.55 : 1
        from: pv.ownMin
        to: pv.ownMax
        step: pv.row.step ?? 0
        integer: pv.isInt
        unit: pv.row.unit ?? ""
        enabled: pv.editable
        cancellable: false
        onCommitted: v => { if (pv.follows || v !== pv.value) Store.setValue(pv.rowKey, v, "") }
        // An arrow key's step is a change of its own (this row has no preview session).
        onPreviewed: v => { if (pv.follows || v !== pv.value) Store.setValue(pv.rowKey, v, "") }
    }
}
