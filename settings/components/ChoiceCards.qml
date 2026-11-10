import QtQuick
import "../core"
import "../core/corner.js" as Corner

// A choice as pictures (session 28; SettingRow.picker, as FrameOutlineCards): each offer of the row as a small card
// that shows what it gives, so the difference is seen before it is picked. `kind` says what the cards draw:
//   chrome       a block and a button as that chrome draws them (flat, keycap, soft, line, bevel, glow, painted, ripped)
//   join         a card and the bar it opens from (as the look draws it, floating, dynamic, connected)
//   join_corner  a card on its bar with the corner's shape on its free corner and its join (round, chamfer, steps, bulge, square)
//   slider       the slider's own face at a level (the part that the shell draws: decor/slider/…)
//   toggle       the switch's own face, on and off
// Pictures in the theme's own colours; the control faces are the real parts, drawn once (nothing moves at rest).
// Keyboard as a radio group: Left/Right move, Space or Return picks; a click picks. It reads and sets its value itself:
// `rowKey` is bound by SettingRow, as every picker's is.
Item {
    id: cards
    property string rowKey: ""
    property string kind: "chrome"
    readonly property var row: { Store.schema; var h = Store.rowOf(cards.rowKey); return h ? h.row : ({}) }
    readonly property var provOf: { Store.config; return Store.prov(cards.rowKey, "") }
    readonly property var choices: cards.row.choices ?? []
    readonly property string current: String(cards.provOf === undefined ? cards.row.default : cards.provOf.value)
    function label(c): string { return I18n.tr(String(c.label)) }
    function value(c): string { return c.value !== undefined ? String(c.value) : String(c) }

    readonly property bool control: kind === "slider" || kind === "toggle"
    readonly property real cardW: control ? 118 : 104
    readonly property real picH: control ? 46 : 64
    implicitHeight: flow.implicitHeight
    height: implicitHeight
    objectName: "choice-cards:" + cards.rowKey
    Accessible.role: Accessible.RadioButton
    Accessible.name: cards.row.label ?? ""

    // The part a control style draws ("" = the built-in drawing): Theme's own table, so the cards cannot differ from
    // what the shell does; Automatic is the look's part.
    function faceOf(v: string): string {
        var t = Theme.controlFaces[cards.kind] || ({})
        if (t[v] !== undefined) return Theme.pascal(t[v])
        var own = Theme.tok("decor." + cards.kind, "")
        return Theme.pascal(own !== "" ? own : (cards.kind === "slider" ? "line" : "switch"))
    }

    Flow {
        id: flow
        width: parent.width
        spacing: Theme.gap
        Repeater {
            model: cards.choices
            delegate: Column {
                id: card
                required property var modelData
                required property int index
                readonly property string v: cards.value(modelData)
                readonly property bool on: v === cards.current
                spacing: 4
                width: cards.cardW
                Item {
                    id: pic
                    objectName: "choice-card:" + card.v
                    width: parent.width
                    height: cards.picH
                    activeFocusOnTab: card.on || (cards.current === "" && card.index === 0)
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: cards.label(card.modelData)
                    Accessible.checked: card.on
                    function pick(): void { if (Store.live) Store.setValue(cards.rowKey, card.v, "") }
                    Keys.onSpacePressed: event => { pick(); event.accepted = true }
                    Keys.onReturnPressed: event => { pick(); event.accepted = true }
                    Keys.onRightPressed: event => { cards.move(card.index, 1); event.accepted = true }
                    Keys.onLeftPressed: event => { cards.move(card.index, -1); event.accepted = true }
                    TapHandler { onTapped: { pic.forceActiveFocus(); pic.pick() } }
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.rSm
                        color: Theme.surface
                        border.width: card.on ? 2 : 1
                        border.color: card.on ? Theme.accent : Theme.outline
                    }
                    // A control's own face.
                    Loader {
                        active: cards.kind === "slider"
                        anchors.centerIn: parent
                        width: parent.width - 24
                        height: 20
                        source: active ? Qt.resolvedUrl("decor/slider/" + cards.faceOf(card.v) + ".qml") : ""
                        onLoaded: item.value = 0.62
                    }
                    Row {
                        visible: cards.kind === "toggle"
                        anchors.centerIn: parent
                        spacing: 10
                        Repeater {
                            model: cards.kind === "toggle" ? [false, true] : []
                            Loader {
                                required property var modelData
                                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                                source: Qt.resolvedUrl("decor/toggle/" + cards.faceOf(card.v) + ".qml")
                                onLoaded: item.checked = modelData
                            }
                        }
                    }
                    // A drawn picture.
                    Canvas {
                        id: cv
                        visible: !cards.control
                        anchors.fill: parent
                        anchors.margins: 3
                        readonly property var inputs: [card.v, cards.kind, Theme.surface, Theme.accent, Theme.fg, Theme.containerHigh,
                            Theme.outline, Theme.dim, Theme.tok("chrome.kind", ""), width, height]
                        onInputsChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            if (cards.kind === "chrome") cards.paintChrome(ctx, width, height, card.v)
                            else if (cards.kind === "join") cards.paintJoin(ctx, width, height, card.v)
                            else if (cards.kind === "join_corner") cards.paintCorner(ctx, width, height, card.v)
                        }
                    }
                    FocusRing { anchors.fill: parent; shown: pic.activeFocus; corner: Theme.rSm }
                }
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    color: card.on ? Theme.fg : Theme.dim
                    font.pixelSize: Theme.fs - 2
                    font.weight: card.on ? Theme.wMedium : Theme.wRegular
                    font.family: Theme.fam(text, Theme.families)
                    text: cards.label(card.modelData)
                }
            }
        }
    }
    function move(from: int, by: int): void {
        var n = cards.choices.length
        if (n === 0) return
        var to = (from + by + n) % n
        if (Store.live) Store.setValue(cards.rowKey, cards.value(cards.choices[to]), "")
        var it = flow.children[to]
        if (it && it.children[0]) it.children[0].forceActiveFocus()
    }

    // ---- the pictures ----
    function rr(ctx, x, y, w, h, r) {
        r = Math.min(r, w / 2, h / 2)
        ctx.beginPath()
        ctx.moveTo(x + r, y); ctx.lineTo(x + w - r, y); ctx.arcTo(x + w, y, x + w, y + r, r)
        ctx.lineTo(x + w, y + h - r); ctx.arcTo(x + w, y + h, x + w - r, y + h, r)
        ctx.lineTo(x + r, y + h); ctx.arcTo(x, y + h, x, y + h - r, r)
        ctx.lineTo(x, y + r); ctx.arcTo(x, y, x + r, y, r)
        ctx.closePath()
    }
    function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a === undefined ? c.a : a) }
    // A chrome: a card (left, larger) and a button on it, each drawn as that chrome draws a block.
    function paintChrome(ctx, w, h, v) {
        var fill = Theme.containerHigh, ink = Theme.fg, acc = Theme.accent
        function block(x, y, bw, bh, r, strong) {
            var c = strong ? acc : fill
            if (v === "keycap") {
                rr(ctx, x, y + 3, bw, bh, r); ctx.fillStyle = ink; ctx.fill()                      // the hard shadow
                rr(ctx, x, y, bw, bh, r); ctx.fillStyle = Qt.lighter(c, 1.25); ctx.fill()          // the ring
                rr(ctx, x + 2.5, y + 2.5, bw - 5, bh - 5, Math.max(0, r - 2.5)); ctx.fillStyle = c; ctx.fill()
                rr(ctx, x + 0.75, y + 0.75, bw - 1.5, bh - 1.5, r); ctx.strokeStyle = ink; ctx.lineWidth = 1.5; ctx.stroke()
            } else if (v === "soft") {
                for (var i = 4; i >= 1; i--) { rr(ctx, x - i, y - i + 3, bw + 2 * i, bh + 2 * i, r + i); ctx.fillStyle = Qt.rgba(0, 0, 0, 0.045); ctx.fill() }
                rr(ctx, x, y, bw, bh, r); ctx.fillStyle = c; ctx.fill()
                rr(ctx, x + 0.5, y + 0.5, bw - 1, bh - 1, r); ctx.strokeStyle = rgba(ink, 0.14); ctx.lineWidth = 1; ctx.stroke()
            } else if (v === "line") {
                rr(ctx, x + 0.75, y + 0.75, bw - 1.5, bh - 1.5, r); ctx.strokeStyle = strong ? acc : ink; ctx.lineWidth = 1.5; ctx.stroke()
            } else if (v === "bevel") {
                ctx.fillStyle = c; ctx.fillRect(x, y, bw, bh)
                ctx.fillStyle = Qt.lighter(c, 1.6); ctx.fillRect(x, y, bw, 2); ctx.fillRect(x, y, 2, bh)
                ctx.fillStyle = Qt.darker(c, 1.9); ctx.fillRect(x, y + bh - 2, bw, 2); ctx.fillRect(x + bw - 2, y, 2, bh)
            } else if (v === "glow") {
                for (var g = 4; g >= 1; g--) { rr(ctx, x - g * 1.5, y - g * 1.5, bw + 3 * g, bh + 3 * g, r + g * 1.5); ctx.strokeStyle = rgba(acc, 0.10); ctx.lineWidth = 3; ctx.stroke() }
                rr(ctx, x, y, bw, bh, r); ctx.fillStyle = rgba(fill, 0.6); ctx.fill()
                rr(ctx, x + 0.75, y + 0.75, bw - 1.5, bh - 1.5, r); ctx.strokeStyle = acc; ctx.lineWidth = 1.5; ctx.stroke()
            } else if (v === "painted") {
                // Strokes of a brush running past the box.
                var n = Math.max(2, Math.round(bh / 7))
                for (var s = 0; s < n; s++) {
                    var yy = y + bh * (s + 0.5) / n, over = 3 + 2 * Math.sin(s * 2.1 + bw)
                    ctx.beginPath(); ctx.moveTo(x - over, yy + Math.sin(s) * 1.2)
                    ctx.quadraticCurveTo(x + bw / 2, yy - 2 + 3 * Math.sin(s * 1.7), x + bw + over * 0.8, yy + Math.cos(s) * 1.5)
                    ctx.strokeStyle = rgba(strong ? acc : Qt.tint(fill, rgba(acc, 0.25)), 0.85); ctx.lineWidth = bh / n + 2.5; ctx.lineCap = "round"; ctx.stroke()
                }
            } else if (v === "ripped") {
                // A sheet torn along its lower and right edge, its white core showing.
                function sheet(d) {
                    ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + bw + d, y)
                    for (var a = 0; a <= 6; a++) ctx.lineTo(x + bw + d + 1.8 * Math.sin(a * 2.9 + bw), y + bh * a / 6)
                    for (var b = 8; b >= 0; b--) ctx.lineTo(x + bw * b / 8, y + bh + d + 2 * Math.sin(b * 2.3 + bh))
                    ctx.closePath()
                }
                sheet(1.6); ctx.fillStyle = Qt.lighter(c, 1.5); ctx.fill()
                sheet(0); ctx.fillStyle = c; ctx.fill()
            } else {
                rr(ctx, x, y, bw, bh, r); ctx.fillStyle = c; ctx.fill()
            }
        }
        var sq = v === "bevel" ? 0 : 7
        block(8, 9, w - 16, h - 20, sq, false)
        block(w - 46, h - 32, 30, 14, v === "bevel" ? 0 : 7, true)
        // (two lines of text on the card)
        ctx.fillStyle = rgba(ink, 0.55); ctx.fillRect(15, 17, w * 0.36, 2.5)
        ctx.fillStyle = rgba(ink, 0.3); ctx.fillRect(15, 24, w * 0.24, 2.5)
    }
    // A connection: the bar along the bottom, a module on it, and the card above — floating (a gap), dynamic (one shape,
    // fillets), connected (one shape, straight); Automatic as the look in effect joins or not.
    function paintJoin(ctx, w, h, v) {
        var fill = Theme.containerHigh, bh = 12, cw = w * 0.5, cx = w - cw - 12, top = 8
        var how = v === "auto" ? (Theme.decor("surface.join", true) !== false ? "dynamic" : "float") : v
        ctx.fillStyle = fill
        ctx.fillRect(0, h - bh, w, bh)
        if (how === "float") { rr(ctx, cx, top, cw, h - bh - top - 5, 6); ctx.fill() }
        else {
            var f = how === "connected" ? 0 : 6
            ctx.beginPath()
            ctx.moveTo(cx - f, h - bh)
            if (f > 0) ctx.arcTo(cx, h - bh, cx, h - bh - f, f); else ctx.lineTo(cx, h - bh)
            ctx.lineTo(cx, top + 6); ctx.arcTo(cx, top, cx + 6, top, 6)
            ctx.lineTo(cx + cw - 6, top); ctx.arcTo(cx + cw, top, cx + cw, top + 6, 6)
            ctx.lineTo(cx + cw, h - bh - f)
            if (f > 0) ctx.arcTo(cx + cw, h - bh, cx + cw + f, h - bh, f); else ctx.lineTo(cx + cw, h - bh)
            ctx.closePath(); ctx.fill()
        }
        ctx.fillStyle = Theme.accent
        rr(ctx, cx + cw / 2 - 5, h - bh + 3, 10, 6, 2); ctx.fill()
        ctx.fillStyle = rgba(Theme.fg, 0.5); ctx.fillRect(cx + 7, top + 8, cw * 0.5, 2.5)
        ctx.fillStyle = rgba(Theme.fg, 0.28); ctx.fillRect(cx + 7, top + 15, cw * 0.35, 2.5)
        if (v === "auto") { ctx.fillStyle = rgba(Theme.fg, 0.45); ctx.font = "9px sans-serif"; ctx.fillText("A", 6, 14) }
    }
    // The corner's shape on a whole piece of the sheet (I489): a card on its bar — its free corner above, the corner
    // where it joins the bar below — drawn by the shell's own post-processor (corner.js), the same code as the card's.
    function paintCorner(ctx, w, h, v) {
        var fill = Theme.containerHigh, r = Math.min(14, h * 0.24), x0 = w * 0.16, x1 = w * 0.62, t = 7, by = h - 13
        var d = "M " + x0 + " " + (t + r) + " A " + r + " " + r + " 0 0 1 " + (x0 + r) + " " + t
              + " L " + (x1 - r) + " " + t + " A " + r + " " + r + " 0 0 1 " + x1 + " " + (t + r)
              + " L " + x1 + " " + (by - r) + " A " + r + " " + r + " 0 0 0 " + (x1 + r) + " " + by
              + " L " + w + " " + by + " L " + w + " " + h + " L 0 " + h + " L 0 " + by
              + " L " + (x0 - r) + " " + by + " A " + r + " " + r + " 0 0 0 " + x0 + " " + (by - r) + " Z"
        var tk = Corner.squircled(d, false, v).trim().split(/\s+/), i = 0, cmd = "", px = 0, py = 0
        ctx.beginPath()
        while (i < tk.length) {
            if (/^[MLACZ]$/.test(tk[i])) { cmd = tk[i]; i++; if (cmd === "Z") { ctx.closePath(); continue } }
            if (cmd === "M") { px = +tk[i]; py = +tk[i + 1]; ctx.moveTo(px, py); i += 2; cmd = "L" }
            else if (cmd === "L") { px = +tk[i]; py = +tk[i + 1]; ctx.lineTo(px, py); i += 2 }
            else if (cmd === "A") {
                // A quarter turn: its centre is the one of (px, y) and (x, py) that is not the bare corner.
                var rad = +tk[i], sweep = +tk[i + 4], ex = +tk[i + 5], ey = +tk[i + 6]
                var k = Corner.cornerOf(px, py, ex, ey, sweep), cxx = px + ex - k.x, cyy = py + ey - k.y
                ctx.arc(cxx, cyy, rad, Math.atan2(py - cyy, px - cxx), Math.atan2(ey - cyy, ex - cxx), sweep === 0)
                px = ex; py = ey; i += 7
            } else if (cmd === "C") {
                ctx.bezierCurveTo(+tk[i], +tk[i + 1], +tk[i + 2], +tk[i + 3], +tk[i + 4], +tk[i + 5])
                px = +tk[i + 4]; py = +tk[i + 5]; i += 6
            } else break
        }
        ctx.fillStyle = fill; ctx.fill()
    }
}
