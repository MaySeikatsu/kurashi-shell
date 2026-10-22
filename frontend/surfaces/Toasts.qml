import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"
import "../components/island"
import "../components/pen.js" as Pen

// Toast stack (focused output) plus the notification center, so shell.qml needs a single line. Expiry is daemon-side: a
// toast exists exactly while its id is in `toasts`. The window is unmapped while no toast is up (Ma).
//
// W34 (docs/ux/motion.md "toasts bud off the bar"): under a top or bottom bar the stack hangs under the island, and a
// new toast drips out of the bar: its shape comes out of the bar's edge under the pill (the pill's foot where the bar's
// groups float), hangs from it with concave fillets, pulls down while its neck thins into a thread, and the thread
// snaps — the card stands free under the bar and springs back to its place (lively: squashed and stretched, from
// tokens), the stub on the bar and the bump on the card melting back. Until it stands free the shape is the card's
// chrome (fill, outline, hard and soft shadow, material), the card's content fades in late. One drip at a time: a newer
// toast waits until the one before has snapped off. The stack moves on springs; a dismissed card is flicked away to the
// side (a swipe goes on in its direction), an expired one drifts and fades — never back into the bar. Without a top or
// bottom bar the stack stands at the top right and cards just appear. Theme.springOn false (motion none) cuts.
// I148: no toasts while the notification center is open, or the right sidebar is open on the toasts' output (it lists
// them); they stay in the stack and come back when it closes (if the daemon still shows them).
Scope {
    id: root
    property var screen: null       // set by shell.qml: the focused output

    Watch { doc: "svc.notifications" }
    Watch { doc: "runtime.ui" }
    readonly property var doc: Store.docs["svc.notifications"] || ({})
    readonly property var ui: Store.docs["runtime.ui"] || ({})
    readonly property int maxToasts: 3
    readonly property bool centerOpen: ui.panel === "notifications"
    // Latched while toasts are up so the stack never jumps outputs mid-notification.
    property var latched: screen
    readonly property string outName: latched ? latched.name : ""
    readonly property bool sidebarHere: ui.sidebar === "right" && (!ui.sidebar_output || ui.sidebar_output === outName)
    readonly property bool held: centerOpen || sidebarHere

    // The toasts the daemon shows, newest first.
    readonly property var wanted: {
        var ids = doc.toasts || [], items = doc.items || [], out = []
        for (var i = 0; i < items.length; i++)
            if (ids.indexOf(items[i].id) >= 0) out.push(items[i])
        out.sort(function (a, b) { return b.time - a.time })
        return out
    }
    readonly property int extra: Math.max(0, wanted.length - maxToasts)

    // The cards on screen (newest first), the ones leaving included until they are gone: {nid, leaving, flick, bud}.
    ListModel { id: cards }
    // id → item for every card in `cards` (a leaving card keeps its own).
    property var cache: ({})
    // A drip has not snapped off yet: newer toasts wait for it.
    property bool budBusy: false
    readonly property bool animated: Theme.springOn && win.drip
    onWantedChanged: sync()
    onHeldChanged: sync()
    function rowOf(id) {
        for (var i = 0; i < cards.count; i++) {
            var r = cards.get(i)
            if (r.nid === id && !r.leaving) return i
        }
        return -1
    }
    // Where a new item goes: before the first card that is older.
    function slotFor(item) {
        for (var i = 0; i < cards.count; i++) {
            var r = cards.get(i)
            if (r.leaving) continue
            var it = cache[r.nid]
            if (!it || it.time < item.time) return i
        }
        return cards.count
    }
    function sync() {
        var top = wanted.slice(0, maxToasts), keep = {}, c = Object.assign({}, cache)
        for (var i = 0; i < top.length; i++) { keep[top[i].id] = true; c[top[i].id] = top[i] }
        if (cards.count === 0 && top.length > 0) latched = screen
        for (var j = cards.count - 1; j >= 0; j--) {
            var r = cards.get(j)
            if (r.leaving || keep[r.nid]) continue
            if (!animated || held || !win.visible) cards.remove(j)
            else cards.setProperty(j, "leaving", true)
        }
        cache = c
        // Additions, the oldest of the new first, each above the older ones. One drip at a time.
        for (var k = top.length - 1; k >= 0; k--) {
            var id = top[k].id
            if (rowOf(id) >= 0) continue
            if (budBusy) break
            var at = slotFor(top[k])
            var bud = animated && !held && at === 0
            cards.insert(at, { nid: id, leaving: false, flick: false, bud: bud })
            if (bud) budBusy = true
        }
        var live = {}
        for (var n = 0; n < cards.count; n++) live[cards.get(n).nid] = true
        var pruned = {}
        for (var key in cache) if (live[key]) pruned[key] = cache[key]
        cache = pruned
    }
    // A dismiss from this card (close or swipe): it is flicked away, not faded.
    function dismiss(id) {
        var i = rowOf(id)
        if (i >= 0) cards.setProperty(i, "flick", true)
        Store.act("notify.dismiss", { id: id })
    }
    function gone(id) {
        for (var i = 0; i < cards.count; i++) if (cards.get(i).nid === id && cards.get(i).leaving) { cards.remove(i); break }
        var c = Object.assign({}, cache)
        if (rowOf(id) < 0) delete c[id]
        cache = c
    }
    function detached() { budBusy = false; Qt.callLater(sync) }

    NotificationCenter { screen: root.screen }

    PanelWindow {
        id: win
        screen: root.latched
        visible: cards.count > 0 && !root.held     // unmapped at idle: mapped-surface budget (docs/BENCH.md)
        // Test only (KURASHI_MORPH_DEBUG=1, frontend/test-toasts.sh): the window coming and going.
        onVisibleChanged: if (Quickshell.env("KURASHI_MORPH_DEBUG") === "1")
            console.log("toasts-window " + (visible ? "up" : "down") + " cards=" + cards.count + " held=" + root.held)
        // K59: this window's tile set, shared by its cards' reliefs, and the pointer light's sensor. K61: the cards carry
        // their own sheet (NotificationCard `carryDy`, the drip's relief).
        property var tileSheet: tilesLoader.item
        readonly property point sheetCarry: Qt.point(0, 0)
        // Made while the window is mapped only: the sheet copies its tiles once (live for a moment), and an unmapped window
        // loses those copies — toasts that came after the window had gone showed no relief (also before W34).
        Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0 && win.visible; sourceComponent: TileSheet {} }
        LightSense {}

        BarConfig { id: bars; screen: win.screen }
        // The drip: a top or bottom bar. Then one vertical edge is anchored (the compositor centres the window on the bar)
        // with margin 0, so the window reaches the bar's edge; it covers the bar's strip only while toasts are up (it is
        // unmapped otherwise) and takes input on the cards only.
        readonly property bool drip: bars.atTop || bars.atBottom
        readonly property bool flip: bars.atBottom
        readonly property bool springing: Theme.springOn && visible
        // Without one: below a top edge, at the right, clear of a right bar (as before W34).
        readonly property int shade: Theme.softR
        readonly property int padR: Math.min(shade, bars.rightInset)
        anchors { top: !bars.atBottom; bottom: bars.atBottom; right: !drip }
        margins {
            top: drip ? 0 : bars.topInset - Math.min(shade, bars.topInset)
            right: drip ? 0 : bars.rightInset - padR
        }

        // ---- geometry, in a top bar's frame ("local": y from the bar's screen edge); mirrored for a bottom bar.
        readonly property real cardW: 340
        // Room beside the stack for a flicked card to fly and fade in (the window is mapped only while toasts are up).
        readonly property int slackX: 160 + Theme.softR
        readonly property var pill: drip && visible ? IslandGeom.pillOf(root.outName) : null
        readonly property real pillW: pill ? pill.w : 96
        readonly property real pillH: pill ? pill.h : Theme.barH - 10
        readonly property real pillTop: (Theme.barH - pillH - Theme.shadowDy) / 2 + (flip ? Theme.shadowDy : 0)
        // The hard shadow falls towards the screen's bottom on either edge (the drip's layer is mirrored for a bottom bar).
        readonly property real shadowSy: (flip ? -1 : 1) * Theme.shadowDy
        // The bar's groups float as blocks (no strip under the island): the drip leaves the pill's foot; else the strip's edge.
        readonly property bool joined: Theme.groups && (Theme.shadowDy > 0 || Theme.softR > 0)
        readonly property real rootY: joined ? pillTop + pillH : Theme.barH
        readonly property real top0: drip ? Theme.barH + Theme.gap + 4 : Math.min(shade, bars.topInset) + (Theme.groups ? Theme.gap : 0)
        readonly property real cardX: drip ? (width - cardW) / 2 : shade
        readonly property real neckCx: width / 2 + (pill ? Math.max(-cardW / 2 + 40, Math.min(cardW / 2 - 40, pill.dx)) : 0)
        // The width the drip leaves the bar with: a strip lets the whole body hang from it; a pill only its flat foot, and the
        // body grows out from under it (as the island's joined shape), so the neck and its fillets stay on that foot.
        readonly property real footW: Math.max(16, pillW - pillH)
        readonly property real rootW: joined ? Math.max(12, footW * 0.45) : 56
        readonly property real startGap: joined ? 4 : 0
        readonly property real fillet: Math.max(10, Theme.rLg)
        // Squash and stretch (I113), from tokens: motion.spring.squash, else derived from the damping (calm 0, lively ~7 %).
        readonly property real squash: Theme.springOn
            ? Theme.tok("motion.spring.squash", Math.max(0, Math.min(0.08, (0.45 - Theme.damping) * 0.4))) : 0
        // How far a drop pulls past its place before the thread snaps.
        readonly property real stretch: 22 + 120 * squash
        // The chrome the shape draws while a card buds: NotificationCard's (outline or a hairline, the panel's fill).
        readonly property real ow: Theme.outlineW > 0 ? Theme.outlineW : 1

        // The stack: each card's place from the ones above it.
        function restOf(index) {
            var y = top0
            for (var j = 0; j < index && j < stack.count; j++) {
                var it = stack.itemAt(j)
                if (it && !it.leaving && it.space > 0) y += it.space + Theme.gap
            }
            return y
        }
        readonly property real stackH: {
            var n = stack.count, h = 0
            for (var j = 0; j < n; j++) {
                var it = stack.itemAt(j)
                if (it && !it.leaving && it.space > 0) h += it.space + Theme.gap
            }
            return Math.max(0, h - Theme.gap)
        }
        readonly property real chipH: root.extra > 0 ? 28 + Theme.gap : 0
        // The lowest thing any card draws (a leaving card keeps its place until it is gone, a drop pulls past its place).
        readonly property real extent: {
            var n = stack.count, b = 0
            for (var j = 0; j < n; j++) {
                var it = stack.itemAt(j)
                if (it) b = Math.max(b, it.extent)
            }
            return b
        }
        implicitWidth: drip ? cardW + 2 * slackX : shade + cardW + Theme.shadowDy + padR
        implicitHeight: Math.ceil(Math.max(top0 + stackH + chipH, extent) + Theme.shadowDy + Theme.softR + (drip ? 24 : shade))
        // A local y (and height) in this window's frame.
        function wy(y, h) { return flip ? height - y - h : y }

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "kurashi-toasts"
        color: "transparent"
        mask: hitRegion
        BackgroundEffect.blurRegion: hitRegion
        Region { id: hitRegion; item: hit }
        // Input on the cards only, never on the bar's strip above them.
        Item {
            id: hit
            x: win.cardX
            y: win.wy(win.top0, height)
            width: win.cardW
            height: Math.max(1, win.stackH + win.chipH)
        }

        Repeater {
            id: stack
            model: cards
            delegate: Item {
                id: d
                required property int index
                required property int nid
                required property bool leaving
                required property bool flick
                required property bool bud
                readonly property var item: root.cache[nid] || ({})
                readonly property real cardH: card.implicitHeight

                // ---- the place in the stack, on a spring.
                readonly property real restY: win.restOf(index)
                property real ry: restY
                Behavior on ry {
                    // Not while a drop is still hanging: it pushes the stack itself (its room changes every frame, and a spring
                    // retargeted every frame never gets going); what it leaves to settle — its pull past its place — springs.
                    enabled: win.springing && !d.leaving && !root.budBusy
                    SpringAnimation { spring: Theme.spring * 1.4; damping: Math.min(1, Theme.damping * 1.2); epsilon: 0.25 }
                }

                // ---- the drip: `t` 0 … 1 (snaps at 0.8), started on the first presented frame; then the spring back.
                property real t: bud ? 0 : 1
                property bool waiting: bud
                property bool detached: !bud
                property bool freed: !bud
                // Test only (KURASHI_MORPH_DEBUG=1): once it stands free, the card's top from the bar's screen edge and its height.
                onFreedChanged: if (freed && Quickshell.env("KURASHI_MORPH_DEBUG") === "1")
                    console.log("toast-card " + nid + " " + Math.round(ly) + " " + Math.round(cardH))
                property real dy: 0
                property real sqz: 0
                Behavior on dy {
                    enabled: d.detached && win.springing
                    SpringAnimation { spring: Theme.spring * 1.6; damping: Theme.damping; epsilon: 0.2 }
                }
                Behavior on sqz {
                    enabled: d.detached && win.springing
                    SpringAnimation { spring: Theme.spring * 2.2; damping: Math.max(0.15, Theme.damping * 0.8); epsilon: 0.002 }
                }
                NumberAnimation {
                    id: budAnim
                    target: d
                    property: "t"
                    from: 0
                    to: 1
                    duration: Math.max(1, Theme.emphMs * 1.6)
                }
                Connections {
                    target: d.waiting ? d.Window.window : null
                    function onFrameSwapped() { d.waiting = false; budAnim.start() }
                }
                Component.onDestruction: if (!d.detached) root.detached()
                onTChanged: {
                    if (!detached && t >= 0.8) detach()
                    if (t >= 1) checkFree()
                }
                // The thread snaps: the card is where the drop pulled it, squashed (lively); both spring back.
                property real snapF1: 0
                property real snapF2: 0
                property real snapCx: 0
                function detach() {
                    snapF1 = f1R
                    snapF2 = f2R
                    snapCx = ncx
                    dy = by0 - ry
                    sqz = -win.squash * 2.5
                    // The stack's springs first: the room the drop took while it pulled is given back on a spring.
                    root.detached()
                    detached = true
                    dy = 0
                    sqz = 0
                }
                function checkFree() { if (t >= 1 && Math.abs(dy) < 0.5 && Math.abs(sqz) < 0.003) freed = true }
                onDyChanged: if (detached && !freed) checkFree()
                onSqzChanged: if (detached && !freed) checkFree()

                // ---- the drip's geometry (local): the body grows out of the bar's edge, pulls down, the neck pinches.
                function clamp01(x) { return Math.max(0, Math.min(1, x)) }
                function lerp(a, b, x) { return a + (b - a) * x }
                readonly property real u: { var x = clamp01(t / 0.42); return 1 - Math.pow(1 - x, 3) }
                readonly property real v: { var x = clamp01((t - 0.12) / 0.43); return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2 }
                readonly property real pc: { var x = clamp01((t - 0.4) / 0.4); return 1 - Math.pow(1 - x, 2.2) }
                // The fillets widen as the neck thins (an hourglass thread before it snaps).
                readonly property real fmax: win.fillet * (1 + 0.8 * pc)
                // After the snap: the stub on the bar and the bump on the card melt back.
                readonly property real melt: detached ? 1 - Math.pow(1 - clamp01((t - 0.8) / 0.2), 2) : 0
                readonly property real bw: detached ? win.cardW * (1 + sqz * 0.5) : lerp(win.rootW, win.cardW, u)
                readonly property real bh: detached ? cardH * (1 - sqz) : lerp(4, cardH, u)
                readonly property real bcx: detached ? win.width / 2 : lerp(win.neckCx, win.width / 2, u)
                readonly property real by0: detached ? ry + dy : lerp(win.rootY + win.startGap, ry + win.stretch, v)
                readonly property real bx0: bcx - bw / 2
                readonly property real bx1: bcx + bw / 2
                readonly property real r: Math.min(Theme.rLg, bw / 2, bh / 2)
                // The neck: from the body's whole width to a thread at the root's centre.
                readonly property real ncx: win.joined ? win.neckCx : lerp(bcx, win.neckCx, pc)
                readonly property real nl: win.joined ? lerp(ncx - win.rootW / 2, ncx, pc) : lerp(bx0, ncx, pc)
                readonly property real nr: win.joined ? lerp(ncx + win.rootW / 2, ncx, pc) : lerp(bx1, ncx, pc)
                readonly property real neckL: by0 - win.rootY
                // Per side: the root's fillet into the bar's edge and the shoulder's fillet into the body's top.
                // On a pill the root's fillets stay on its flat foot.
                readonly property real footRoom: win.joined ? Math.max(0, (win.footW - (nr - nl)) / 2) : fmax
                function f1Of(s) {
                    if (s < 0.5) return Math.min(fmax, footRoom, Math.max(0, (by0 + bh - r - win.rootY) * 0.5))
                    return Math.min(fmax, footRoom, Math.max(0, neckL * 0.5))
                }
                function f2Of(s, f1) { return s < 0.5 ? 0 : Math.min(fmax, s * 0.5, Math.max(0, neckL - f1)) }
                readonly property real sL: Math.max(0, nl - bx0)
                readonly property real sR: Math.max(0, bx1 - nr)
                readonly property real f1L: f1Of(sL)
                readonly property real f1R: f1Of(sR)
                readonly property real f2L: f2Of(sL, f1L)
                readonly property real f2R: f2Of(sR, f1R)

                function f(x) { return Math.round(x * 100) / 100 }
                function arc(rr, sweep, x, y) {
                    return rr > 0.05 ? " A " + f(rr) + " " + f(rr) + " 0 0 " + sweep + " " + f(x) + " " + f(y) : " L " + f(x) + " " + f(y)
                }
                // The contour inset by `dd`, moved down by `sy` (the hard shadow), clockwise from the right root's top to the
                // left root's top (the neck, the shoulders and the body). `close`: closed along the bar's edge, `ow` into it
                // (the fill covers the bar's rule or the pill's outline across the neck), else open (the outline).
                function attached(dd, sy, close) {
                    var E = win.rootY + sy
                    var X0 = bx0 + dd, X1 = bx1 - dd, Y0 = by0 + dd + sy, Y1 = by0 + bh - dd + sy
                    if (X1 - X0 < 1 || Y1 - E < 1) return ""
                    var rb = Math.max(0, Math.min(r - dd, (X1 - X0) / 2, (Y1 - Y0) / 2))
                    var s = (close ? "M " + f(nr + f1R) + " " + f(E - win.ow) + " L " : "M ") + f(nr + f1R) + " " + f(E - dd)
                    s += arc(f1R + dd, 0, nr - dd, E + f1R)
                    if (sR >= 0.5) {
                        var tr = Math.max(0, Math.min(r, sR - f2R) - dd)
                        s += " L " + f(nr - dd) + " " + f(by0 - f2R + sy) + arc(f2R + dd, 0, nr + f2R, Y0)
                        s += " L " + f(X1 - tr) + " " + f(Y0) + arc(tr, 1, X1, Y0 + tr)
                    }
                    s += " L " + f(X1) + " " + f(Y1 - rb) + arc(rb, 1, X1 - rb, Y1) + " L " + f(X0 + rb) + " " + f(Y1) + arc(rb, 1, X0, Y1 - rb)
                    if (sL >= 0.5) {
                        var tl = Math.max(0, Math.min(r, sL - f2L) - dd)
                        s += " L " + f(X0) + " " + f(Y0 + tl) + arc(tl, 1, X0 + tl, Y0)
                        s += " L " + f(nl - f2L) + " " + f(Y0) + arc(f2L + dd, 0, nl + dd, by0 - f2L + sy)
                    }
                    s += " L " + f(nl + dd) + " " + f(E + f1L) + arc(f1L + dd, 0, nl - f1L, E - dd)
                    if (close) s += " L " + f(nl - f1L) + " " + f(E - win.ow) + " Z"
                    return s
                }
                // Free: the card's rounded rect, with the bump the thread left on its top melting back.
                function free(dd, sy) {
                    var X0 = bx0 + dd, X1 = bx1 - dd, Y0 = by0 + dd + sy, Y1 = by0 + bh - dd + sy
                    if (X1 - X0 < 1 || Y1 - Y0 < 1) return ""
                    var rr = Math.max(0, Math.min(r - dd, (X1 - X0) / 2, (Y1 - Y0) / 2))
                    var ab = (snapF2 + 2) * (1 - melt), hb = snapF2 * 0.7 * (1 - melt)
                    var cx = Math.max(X0 + rr + ab, Math.min(X1 - rr - ab, snapCx))
                    var s = "M " + f(X0 + rr) + " " + f(Y0)
                    if (hb > 0.3 && ab > 1) s += " L " + f(cx - ab) + " " + f(Y0) + arc((ab * ab + hb * hb) / (2 * hb), 1, cx + ab, Y0)
                    s += " L " + f(X1 - rr) + " " + f(Y0) + arc(rr, 1, X1, Y0 + rr) + " L " + f(X1) + " " + f(Y1 - rr) + arc(rr, 1, X1 - rr, Y1)
                    s += " L " + f(X0 + rr) + " " + f(Y1) + arc(rr, 1, X0, Y1 - rr) + " L " + f(X0) + " " + f(Y0 + rr) + arc(rr, 1, X0 + rr, Y0)
                    return s + " Z"
                }
                // The stub the thread left on the bar, melting back into it.
                function stub(sy, close) {
                    var as = (snapF1 + 2) * (1 - melt), hs = snapF1 * 0.9 * (1 - melt), E = win.rootY + sy
                    if (as < 1 || hs < 0.3) return ""
                    var R = (as * as + hs * hs) / (2 * hs)
                    if (!close) return "M " + f(snapCx + as) + " " + f(E) + arc(R, 1, snapCx - as, E)
                    return "M " + f(snapCx - as) + " " + f(E - win.ow) + " L " + f(snapCx + as) + " " + f(E - win.ow) + " L " + f(snapCx + as)
                        + " " + f(E) + arc(R, 1, snapCx - as, E) + " Z"
                }
                readonly property bool drawn: !freed && !leaving && win.drip
                readonly property string fillPath: !drawn ? "" : (detached ? free(0, 0) + " " + stub(0, true) : attached(0, 0, true))
                readonly property string linePath: !drawn ? "" : (detached ? free(win.ow / 2, 0) + " " + stub(0, false) : attached(win.ow / 2, 0, false))
                readonly property string shadowPath: !drawn || Theme.shadowDy <= 0 ? ""
                    : (detached ? free(0, win.shadowSy) : attached(0, win.shadowSy, false) + " Z")
                readonly property color lineColor: card.urgent ? Theme.accent : (Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline)

                // ---- where the card is drawn (local top), and its space in the stack.
                readonly property real ly: detached ? ry + dy : by0
                // A drop makes room as it grows (and pulls past its place), so the stack is pushed down rather than covered.
                readonly property real space: leaving ? 0 : (detached ? cardH : bh + Math.max(0, by0 - restY))
                readonly property real extent: leaving ? frozenY + cardH : Math.max(ly + cardH * (detached ? 1 - Math.min(0, sqz) : 1), by0 + bh)
                // A drop is drawn over the stack it pushes down.
                z: drawn ? 1 : 0
                // Leaving: flicked to the side (a dismiss here), or drifting off as it fades (expired, or dismissed elsewhere).
                property real fx: 0
                property real fade: 1
                property real frozenY: 0
                onLeavingChanged: if (leaving) {
                    frozenY = ly
                    leave.start()
                }
                ParallelAnimation {
                    id: leave
                    NumberAnimation {
                        target: d; property: "fx"
                        to: d.flick ? Math.max(0, win.slackX - 8 - Math.max(0, card.x)) : 28
                        duration: d.flick ? Theme.stdMs : Theme.emphMs
                        easing.type: d.flick ? Easing.OutQuad : Easing.OutCubic
                    }
                    NumberAnimation {
                        target: d; property: "fade"; to: 0
                        duration: d.flick ? Theme.stdMs : Theme.emphMs
                        easing.type: Easing.InOutQuad
                    }
                    onFinished: root.gone(d.nid)
                }

                // The drip's shape (in the mirrored layer for a bottom bar).
                Item {
                    id: dripLayer
                    visible: d.drawn
                    width: win.width
                    height: win.height
                    transform: Scale { yScale: win.flip ? -1 : 1; origin.y: win.height / 2 }
                    SoftShadow {
                        x: d.bx0
                        y: d.by0
                        width: d.bw
                        height: d.bh
                        radius: d.r
                        amount: d.drawn ? 1 : 0
                        direction: win.flip ? -1 : 1
                    }
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeWidth: -1
                            strokeColor: "transparent"
                            fillColor: Theme.shadowDy > 0 ? Theme.line : "transparent"
                            PathSvg { path: d.shadowPath }
                        }
                        ShapePath {
                            strokeWidth: -1
                            strokeColor: "transparent"
                            fillColor: Theme.panel
                            PathSvg { path: d.fillPath }
                        }
                        ShapePath {
                            strokeWidth: Theme.penOutline ? -1 : win.ow
                            strokeColor: Theme.penOutline ? "transparent" : d.lineColor
                            fillColor: "transparent"
                            capStyle: ShapePath.FlatCap
                            joinStyle: ShapePath.RoundJoin
                            PathSvg { path: Theme.penOutline ? "" : d.linePath }
                        }
                    }
                    // K62: the pen draws the outline (the same contour) where it is in effect.
                    Loader {
                        anchors.fill: parent
                        active: Theme.penOutline && d.drawn
                        sourceComponent: PenOutline {
                            color: d.lineColor
                            lineWidth: win.ow
                            seed: d.item && d.item.id !== undefined ? (Math.imul(Number(d.item.id) | 0, 0x9E3779B1) >>> 1) : 0
                            paths: {
                                var subs = Pen.svgPaths(d.linePath), out = []
                                for (var i = 0; i < subs.length; i++) out.push({ points: subs[i].pts, closed: subs[i].closed, width: win.ow })
                                return out
                            }
                        }
                    }
                }
                // K59/K61: the material on the drop's body while the shape draws it, carried with it.
                Loader {
                    active: Theme.texShell && d.drawn && d.bw > 4 && d.bh > 4
                    x: d.bx0 + win.ow
                    y: win.wy(d.by0 + win.ow, height)
                    width: Math.max(1, d.bw - 2 * win.ow)
                    height: Math.max(1, d.bh - 2 * win.ow)
                    z: Theme.texText ? 2 : 0
                    sourceComponent: Relief {
                        radius: Math.max(0, d.r - win.ow)
                        carry: Qt.point(d.bcx - win.width / 2, (win.flip ? -1 : 1) * (d.by0 - d.restY))
                    }
                }

                // The card's slot (its place); the card itself moves only when it is swiped (NotificationCard's x).
                Item {
                    x: win.cardX + d.fx
                    y: win.wy(d.leaving ? d.frozenY : d.ly, card.height)
                    width: win.cardW
                    height: card.height
                    transform: Scale {
                        origin.x: win.cardW / 2
                        origin.y: win.flip ? card.height : 0
                        xScale: d.detached ? 1 + d.sqz * 0.5 : 1
                        yScale: d.detached ? 1 - d.sqz : 1
                    }
                    NotificationCard {
                        id: card
                        item: d.item
                        width: win.cardW
                        bare: d.drawn
                        contentOpacity: d.freed ? 1 : d.clamp01((d.t - 0.5) / 0.25)
                        carryDy: (win.flip ? -1 : 1) * (d.ly - d.restY)
                        swipeable: !d.leaving
                        onDismissed: root.dismiss(d.nid)
                        onInvoked: key => Store.act("notify.invoke", { id: d.nid, key: key })
                    }
                }
                // A leaving card's chrome fades with it (group opacity only while it leaves, K16).
                opacity: d.leaving ? d.fade : 1
            }
        }
        Chip {
            visible: root.extra > 0
            x: win.cardX + win.cardW - width
            y: win.wy(win.top0 + win.stackH + Theme.gap, height)
            text: "+" + root.extra
        }
    }
}
