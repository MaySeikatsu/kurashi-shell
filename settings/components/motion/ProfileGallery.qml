import QtQuick
import "../../core"
import ".."
import "curvemath.js" as CM
import "reasons.js" as RS

// The motion profiles as cards (brief §8 item 2): one per motion pack the daemon offers (`motion.profiles`), each with its
// name and what it does; the one in effect has a ring and a check, the one the style recommends says so (from the key's
// layers, cfg.why). Picking one is a single change, with Undo right under the cards. Keyboard as a radio group: Tab
// enters at the chosen card, arrows move, Return or Space picks. The picker of theme.motion.profile (SettingRow.picker):
// the row's provenance, Reset and reasons (reduce motion forces `reduced`) stay under it. A card's moving thumbnail comes
// with the preview stage (W59.2's forms); until the daemon publishes each pack's curves only the profile in effect is drawn.
Column {
    id: pg
    property string rowKey: "theme.motion.profile"
    signal openKey(string key)
    objectName: "profiles:" + pg.rowKey
    spacing: Theme.gap

    readonly property var row: { Store.schema; var h = Store.rowOf(pg.rowKey); return h ? h.row : ({}) }
    readonly property var prov: { Store.config; return Store.prov(pg.rowKey, "") }
    readonly property string current: pg.prov && typeof pg.prov.value === "string" ? pg.prov.value : (pg.row.default ?? "")
    readonly property var own: RS.extra(pg.prov)
    readonly property bool inert: { Store.config; return pg.own !== null || Store.inertReasons(pg.row, "").some(function (x) {
        return x.kind !== "pending" && x.kind !== "unavailable" && x.kind !== "mod_off" }) }
    readonly property bool editable: !pg.inert && Store.live
    // Packs that cannot run yet (a draft whose forms are not built: `enabled: false` with its reason) stay in the gallery,
    // greyed with why, after the ones that can (W59.1).
    readonly property var offers: {
        var list = pg.row.choices ?? []
        return list.filter(function (o) { return o.enabled !== false }).concat(list.filter(function (o) { return o.enabled === false }))
    }

    // The style's recommendation: the value of the theme layer (`style:<name>`) among the key's layers.
    readonly property var layers: { Store.explained; return Store.explained[pg.rowKey + "|"] || [] }
    readonly property var styleLayer: {
        for (var i = 0; i < pg.layers.length; i++) {
            var s = pg.layers[i].source
            if (s && s.kind === "theme" && /^style:/.test(s.name || "")) return pg.layers[i]
        }
        return null
    }
    readonly property string recommended: pg.styleLayer ? String(pg.styleLayer.value) : ""
    readonly property string styleName: pg.styleLayer ? Store.packLabel("styles", pg.styleLayer.source.name.substring(6)) : ""
    function ask() { Store.explain(pg.rowKey, "", null) }
    Component.onCompleted: ask()
    Connections {
        target: Store
        function onConfigChanged() { Qt.callLater(pg.ask) }
    }

    // Undo right after a pick (brief §8: "a single config op with an undo toast"): offered while the pick is the last change.
    property string picked: ""
    property string before: ""
    function pick(id) {
        var o = pg.offers.find(function (x) { return x.value === id })
        if (!pg.editable || id === pg.current || (o && o.enabled === false)) return
        pg.before = pg.current
        pg.picked = id
        Store.setValue(pg.rowKey, id, "")
    }
    onCurrentChanged: if (pg.current !== pg.picked) pg.picked = ""

    readonly property int cardW: 168
    readonly property int cols: Math.max(1, Math.floor((width + Theme.gap) / (cardW + Theme.gap)))
    function focusAt(i) {
        var it = rep.itemAt(Math.max(0, Math.min(pg.offers.length - 1, i)))
        if (it) it.forceActiveFocus()
    }
    // The open curve of the profile in effect (theme tokens), drawn on its card.
    readonly property var openCurve: { Store.theme; var e = CM.inEffect(Store.theme.tokens, "open"); return e ? e.curve : null }

    Flow {
        width: parent.width
        spacing: Theme.gap
        opacity: pg.editable ? 1 : 0.5
        Accessible.role: Accessible.List
        Accessible.name: I18n.tr(pg.row.label ?? "")
        Repeater {
            id: rep
            model: pg.offers
            delegate: RoundBox {
                id: card
                required property var modelData
                required property int index
                readonly property bool on: modelData.value === pg.current
                readonly property bool styles: modelData.value === pg.recommended
                readonly property string name: I18n.tr(modelData.label)
                readonly property string desc: I18n.has(modelData.label + ".desc") ? I18n.tr(modelData.label + ".desc") : ""
                readonly property bool pickable: modelData.enabled !== false
                readonly property string why: modelData.reason ? I18n.tr(modelData.reason) : ""
                objectName: "profile:" + modelData.value
                width: pg.cardW
                height: Math.max(112, body.implicitHeight + 2 * Theme.gap)
                radius: Theme.rSm
                opacity: pickable || on ? 1 : 0.55
                color: on ? Theme.container : Theme.containerHigh
                border.width: on ? 2 : 1
                border.color: on ? Theme.accent : Theme.outline
                activeFocusOnTab: pg.editable && (on || (pg.offers.every(function (o) { return o.value !== pg.current }) && index === 0))
                Accessible.role: Accessible.RadioButton
                Accessible.name: card.name + (card.styles ? ", " + I18n.fmt("motion.ui.profile.recommended", { style: pg.styleName }) : "")
                Accessible.description: card.desc + (card.why !== "" ? " " + card.why : "")
                Accessible.checked: on
                Keys.onLeftPressed: event => { pg.focusAt(index - 1); event.accepted = true }
                Keys.onRightPressed: event => { pg.focusAt(index + 1); event.accepted = true }
                Keys.onUpPressed: event => { pg.focusAt(index - pg.cols); event.accepted = true }
                Keys.onDownPressed: event => { pg.focusAt(index + pg.cols); event.accepted = true }
                Keys.onReturnPressed: event => { pg.pick(modelData.value); event.accepted = true }
                Keys.onEnterPressed: event => { pg.pick(modelData.value); event.accepted = true }
                Keys.onSpacePressed: event => { pg.pick(modelData.value); event.accepted = true }

                Column {
                    id: body
                    x: Theme.gap
                    y: Theme.gap
                    width: parent.width - 2 * Theme.gap
                    spacing: 2
                    // The curve the profile in effect opens on; the other cards get theirs with the daemon's pack previews.
                    Canvas {
                        id: still
                        visible: card.on && pg.openCurve !== null && pg.openCurve.kind !== "spring_q"
                        width: parent.width
                        height: visible ? 30 : 0
                        renderStrategy: Canvas.Cooperative
                        property var c: pg.openCurve
                        onCChanged: requestPaint()
                        onVisibleChanged: if (visible) requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            if (!c || c.kind === "spring_q") return
                            var X = function (x) { return x * width }
                            var Y = function (y) { return height - (y + 0.2) / 1.4 * height }
                            ctx.strokeStyle = Theme.accent
                            ctx.lineWidth = 2
                            ctx.beginPath()
                            ctx.moveTo(X(0), Y(0))
                            var span = CM.spanOf(c, 500)
                            for (var i = 1; i <= 40; i++) ctx.lineTo(X(i / 40), Y(CM.sample(c, i / 40, span)))
                            ctx.stroke()
                        }
                    }
                    MotionText {
                        width: parent.width
                        font.weight: card.on ? Font.DemiBold : Font.Normal
                        text: (card.on ? "✓ " : "") + card.name
                    }
                    MotionText {
                        visible: card.desc !== ""
                        width: parent.width
                        small: true
                        color: Theme.dim
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        text: card.desc
                    }
                    MotionText {
                        visible: card.styles
                        width: parent.width
                        small: true
                        color: Theme.fg
                        text: "★ " + I18n.fmt("motion.ui.profile.recommended", { style: pg.styleName })
                    }
                    // Why it cannot be picked yet (the daemon's reason: its forms are not built).
                    MotionText {
                        visible: card.why !== ""
                        width: parent.width
                        small: true
                        color: Theme.dim
                        text: "⊘ " + card.why
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: pg.editable && card.pickable
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pg.pick(card.modelData.value)
                }
                FocusRing {
                    anchors.fill: parent
                    shown: card.activeFocus
                    corner: Theme.rSm
                }
            }
        }
    }
    Row {
        visible: pg.picked !== "" && pg.picked === pg.current && Store.canUndo
        spacing: Theme.gap
        MotionText {
            anchors.verticalCenter: parent.verticalCenter
            small: true
            text: I18n.fmt("motion.ui.profile.picked", { name: pg.picked === "" ? "" : (I18n.has("config.choice.motion.profile." + pg.picked)
                ? I18n.tr("config.choice.motion.profile." + pg.picked) : pg.picked) })
        }
        LinkText {
            objectName: "profile-undo"
            text: I18n.tr("motion.ui.profile.undo")
            onActivated: { pg.picked = ""; Store.undo() }
        }
    }
    MotionReason { reason: pg.own; onOpenKey: key => pg.openKey(key) }
}
