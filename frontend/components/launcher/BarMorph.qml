import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../core"
import ".."
import "../island"

// One surface that grows out of the bar (W34, docs/ux/motion.md "the bar reaches out"): the launcher and the notification
// centre. The island's own machinery (Stage, W21/K42) — one MorphShape from the island pill's rect (IslandGeom) to the
// card's, width and height on their own springs (width leads on the way out, height on the way back, Capsule), the liquid
// neck at the bar's edge (strip) or the neck under the island's block (joined, keycap and soft chrome), the pill's face in
// the shape's head, the content cut to the shape and faded in late, out first — for a surface that is not the Stage.
//
// The owner is a layer window that, while `layout` (the shape is out), anchors one bar edge only (the compositor centres it
// on its output, so the shape's box is centred on the bar: MorphShape opens the bar's rule from its own centre) with
// margin 0 on that edge, and takes this item's size: the window covers the bar's strip above the card only while the
// shape is out (K16; idle it keeps the card's size, or is unmapped). Its content goes in as children: they land in a `cardW` x `cardH` box where the grown
// card stands, cut to the shape while it moves. Without a top or bottom bar (`morph` false) the card slides in instead and
// the owner draws its own chrome (`morph` tells it which).
//
// While the shape is out it holds the island (IslandGeom.takenOn — set here imperatively, the Stage binds it: never both
// at once, and released only while it still names this output), so the bar hides its pill and opens its rule under the
// shape, and the shape's head shows the pill's face: one island on screen. A pill already held by the Stage is left alone
// (the shape then grows without a face). No pill on this output: the shape grows from the bar's centre.
//
// Profiles from tokens only (rule 4): the springs are Theme.spring/damping (calm settles, lively bounces, soft-limited to
// 8 %); `squash` (motion.spring.squash, else derived from the damping: 0 for calm, ~7 % for lively) narrows the shape while
// it lengthens fast and lets it bulge as it lands, and the neck swells and thins once with the landing's overshoot.
// Theme.springOn false (motion none, reduce motion) cuts. Ma: nothing runs at rest; paths change only while it morphs.
Item {
    id: m

    // The output's name (IslandGeom's key), whether its bar is at the bottom (the shape mirrored), whether it is at the top
    // or bottom at all (else the slide).
    property string outName: ""
    property bool flip: false
    property bool onBar: false
    // Wanted open (the owner's state from the daemon).
    property bool open: false
    // The card at rest.
    property real cardW: 360
    property real cardH: 200
    // The slide's travel and the window's room round the card in the fallback (the soft shadow).
    property int slide: 12
    property int shade: Theme.softR
    // The fallback's scale on the way in (the launcher's 0.96 → 1), 1 for none.
    property real slideScale: 1
    default property alias content: inner.data
    // The card's rest rect as an item (input mask and blur region).
    readonly property alias cardItem: card

    readonly property bool morph: onBar
    // On screen: opening, open or folding back.
    property bool shown: false
    property bool gate: false
    // The window's size while shown in the morph (the bar's strip, the card, the springs' slack).
    readonly property real winW: morphW
    readonly property real winH: morphH
    // The fallback's progress (0 hidden … 1 in).
    property real p: 0
    // The content's fade (late in, first out).
    property real contentP: 0
    // At rest open: the springs have arrived (the owner turns its blur on only then: the shape changes size every frame).
    readonly property bool settled: !morph ? (shown && p >= 1) : (shown && open && !gate && Math.abs(mw - 1) < 0.004 && Math.abs(mh - 1) < 0.004)
    // How far the card's body is from its rest place, in output axes (K61: the owner publishes it as its window's carry
    // while the card slides; the shape's own relief carries `shapeCarry`).
    readonly property point carry: morph ? Qt.point(0, 0) : Qt.point(0, -slide * (1 - p))
    signal hidden()

    // ---- origin: the island pill on this output (read on open, followed only while shown, Ma), else the bar's centre.
    property var pillGeom: null
    Binding {
        target: m
        property: "pillGeom"
        value: IslandGeom.pillOf(m.outName)
        when: m.shown
        restoreMode: Binding.RestoreNone
    }
    readonly property real barHt: Theme.barH
    readonly property real pillW: pillGeom ? pillGeom.w : Math.min(96, cardW)
    readonly property real pillH: pillGeom ? pillGeom.h : barHt - 10
    readonly property real pillDx: pillGeom ? pillGeom.dx : 0
    readonly property real pillTop: (barHt - pillH - Theme.shadowDy) / 2 + (flip ? Theme.shadowDy : 0)
    readonly property real cardTop: barHt + 4
    readonly property bool lifted: Theme.shadowDy > 0 || Theme.softR > 0
    readonly property bool joined: Theme.groups && lifted
    readonly property bool boxed: Theme.outlineW > 0 && !lifted
    readonly property real neckR: joined ? 0 : Theme.rLg
    readonly property int slackX: 16 + Theme.softR
    readonly property int slackY: 40
    readonly property real morphW: 2 * Math.ceil(Math.max(cardW / 2 + neckR + slackX, Math.abs(pillDx) + pillW / 2 + 8))
    readonly property real morphH: Math.ceil(cardTop + cardH + Theme.shadowDy + slackY)

    // ---- the springs (0 = the pill, 1 = the card), as the Stage's.
    property real mw: 0
    property real mh: 0
    property bool expanding: true
    // This shape holds the island (see the header).
    property bool holds: false
    readonly property bool springing: shown && !gate && Theme.springOn
    Behavior on mw {
        enabled: m.springing
        SpringAnimation {
            spring: Theme.spring * (m.expanding ? 1.3 : 1.2)
            damping: Math.min(1, Theme.damping * (m.expanding ? 1 : 1.25))
            epsilon: 0.002
        }
    }
    Behavior on mh {
        enabled: m.springing
        SpringAnimation {
            spring: Theme.spring * (m.expanding ? 1.0 : 1.6)
            damping: Math.min(1, Theme.damping * (m.expanding ? 1.25 : 1))
            epsilon: 0.002
        }
    }
    function take() {
        if (outName !== "" && IslandGeom.takenOn === "") { IslandGeom.takenOn = outName; holds = true }
    }
    function release() {
        if (holds && IslandGeom.takenOn === outName) IslandGeom.takenOn = ""
        holds = false
    }
    Component.onDestruction: release()

    // Test only (KURASHI_MORPH_DEBUG=1): when the growth starts, and the springs twice a second while the shape is out.
    readonly property bool debugLog: Quickshell.env("KURASHI_MORPH_DEBUG") === "1"
    property double openedAt: 0
    Timer {
        interval: 500
        repeat: true
        running: m.debugLog && m.shown
        onTriggered: console.log("bar-morph mw=" + m.mw.toFixed(3) + " mh=" + m.mh.toFixed(3) + " content=" + m.contentP.toFixed(2)
            + " open=" + m.open + " gate=" + m.gate + " holds=" + m.holds + " card=" + m.cardW + "x" + m.cardH)
    }
    Connections {
        target: m.debugLog && m.shown ? m.Window.window : null
        function onFrameSwapped() {
            var t = Date.now() - m.openedAt
            if (t < 900) console.log("bar-morph frame +" + t + " ms mw=" + m.mw.toFixed(3) + " mh=" + m.mh.toFixed(3))
        }
    }
    onOpenChanged: { openedAt = Date.now(); follow() }
    function follow() {
        if (open) {
            pillGeom = IslandGeom.pillOf(outName)
            handBack.stop()
            if (morph) {
                if (!shown) { mw = 0; mh = 0; gate = true; shown = true }
                else { expanding = true; mw = 1; mh = 1 }
            } else {
                anim.stop()
                if (!shown) { p = 0; gate = true; shown = true }
                else { anim.from = p; anim.to = 1; anim.start() }
            }
        } else if (shown) {
            gate = false
            if (morph) { expanding = false; mw = 0; mh = 0; checkFolded() }
            else { anim.stop(); anim.from = p; anim.to = 0; anim.start() }
        }
    }
    // The bar moved while the card is out: no morph across edges, the card goes and comes back in the new manner.
    onMorphChanged: if (shown) {
        handBack.stop(); anim.stop(); release()
        shown = false; gate = false; mw = 0; mh = 0; p = 0
        if (open) follow(); else m.hidden()
    }
    NumberAnimation {
        id: anim
        target: m
        property: "p"
        duration: Theme.stdMs
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.enterCurve
        onFinished: if (m.p <= 0 && !m.open) { m.shown = false; m.hidden() }
    }
    // The growth starts on the first presented frame (the window is mapped and sized by then), not on the request.
    Connections {
        target: m.gate ? m.Window.window : null
        function onFrameSwapped() {
            if (!m.gate) return
            m.gate = false
            if (m.debugLog) console.log("bar-morph gate " + m.outName + " +" + (Date.now() - m.openedAt) + " ms")
            if (m.morph) { m.take(); m.expanding = true; m.mw = 1; m.mh = 1 }
            else { anim.from = m.p; anim.to = 1; anim.start() }
        }
    }
    // Folded back: the pill goes back to the bar first and the shape a moment later, so the screen never shows no island.
    onMwChanged: checkFolded()
    onMhChanged: { trackSpeed(); checkFolded() }
    function checkFolded() {
        if (open || !shown || !morph || handBack.running) return
        if (mw <= 0.02 && mh <= 0.02) { release(); handBack.start() }
    }
    Timer {
        id: handBack
        interval: 80
        onTriggered: {
            if (m.open) return
            m.shown = false
            m.mw = 0
            m.mh = 0
            m.hidden()
        }
    }

    // ---- squash and stretch (I113), from tokens: the height's speed (progress per second, smoothed) narrows the shape as
    // it lengthens; the overshoot past 1 widens it as it lands.
    readonly property real squash: Theme.springOn
        ? Theme.tok("motion.spring.squash", Math.max(0, Math.min(0.08, (0.45 - Theme.damping) * 0.4))) : 0
    property real speed: 0
    property real lastMh: 0
    property double lastT: 0
    function trackSpeed() {
        if (squash <= 0 || !shown) { speed = 0; return }
        var t = Date.now(), dt = t - lastT
        if (dt > 0 && dt < 100) speed = speed * 0.5 + 0.5 * (mh - lastMh) * 1000 / dt
        else speed = 0
        lastMh = mh
        lastT = t
    }

    // ---- the shape's geometry, in a top bar's frame (the box is mirrored for a bottom bar).
    function soft(v) { return v > 1 ? 1 + Math.min((v - 1) * 0.6, 0.08) : Math.max(0, v) }
    function lerp(a, b, t) { return a + (b - a) * t }
    readonly property real ew: soft(mw)
    readonly property real eh: soft(mh)
    readonly property real tw: Math.max(0, Math.min(1, mw))
    readonly property real th: Math.max(0, Math.min(1, mh))
    // Narrower while it lengthens fast, wider while the height overshoots (both 0 without squash).
    readonly property real squashK: squash <= 0 ? 0
        : Math.max(-1.5 * squash, Math.min(squash, -squash * Math.max(0, speed) / 6 + 4 * squash * Math.max(0, eh - 1)))
    readonly property real shapeW: lerp(pillW, cardW, ew) * (1 + squashK * tw)
    readonly property real shapeH: lerp(pillH, cardTop + cardH - pillTop, eh)
    readonly property real shapeCx: morphW / 2 + lerp(pillDx, 0, tw)
    readonly property real pillR: Math.min(Theme.rFull, pillH / 2)
    readonly property real pillCx: morphW / 2 + pillDx
    readonly property real bodyTop: joined ? lerp(pillTop + pillH, cardTop, eh) : pillTop
    readonly property real bodyH: joined ? Math.max(0, lerp(0, cardH, eh)) : shapeH
    readonly property point shapeCarry: Qt.point(shapeCx - morphW / 2, (flip ? -1 : 1) * (bodyTop + bodyH - cardTop - cardH))
    // The neck swells once as the card lands (the height's overshoot) — lively only, through `squash`.
    readonly property real wobble: squash > 0 ? Math.max(-0.5, Math.min(1, (eh - 1) * 12)) : 0
    readonly property color shapeFill: {
        var c = Qt.tint(boxed ? Theme.surface : Theme.containerHigh, Qt.alpha(Theme.container, tw))
        return Qt.alpha(c, Theme.panel.a)
    }
    // The content comes in once the shape has nearly grown (fade + 0.98 → 1) and leaves first.
    readonly property bool contentWanted: morph ? (open && shown && !gate && mw > 0.72 && mh > 0.6) : true
    onContentWantedChanged: contentP = contentWanted ? 1 : 0
    Behavior on contentP {
        enabled: m.morph && m.shown && Theme.quickMs > 0
        NumberAnimation { duration: m.contentWanted ? 160 : 90; easing.type: Easing.OutCubic }
    }

    // The bar's strip and the slack only while the shape is out (K16); idle, the card's size (the owner's window keeps no strip).
    readonly property bool layout: morph && shown
    width: layout ? morphW : cardW + 2 * shade
    height: layout ? morphH : cardH + 2 * shade

    Item {
        id: shapeBox
        visible: m.shown && m.morph
        width: m.morphW
        height: m.morphH
        transform: Scale { yScale: m.flip ? -1 : 1; origin.y: m.morphH / 2 }
        SoftShadow {
            visible: m.joined
            x: m.pillCx - m.pillW / 2
            y: m.pillTop
            width: m.pillW
            height: m.pillH
            radius: m.pillR
            direction: m.flip ? -1 : 1
        }
        SoftShadow {
            visible: shape.h > 1
            x: shape.x0
            y: shape.y0
            width: shape.w
            height: shape.h
            radius: Math.min(shape.rTop, shape.rBot)
            direction: m.flip ? -1 : 1
        }
        MorphShape {
            id: shape
            visible: shapeBox.visible
            anchors.fill: parent
            joined: m.joined
            hx0: m.pillCx - m.pillW / 2
            hy0: m.pillTop
            hw: m.pillW
            hh: m.pillH
            hr: m.pillR
            neckF: Theme.rLg / 2 * (1 + 0.6 * m.wobble)
            x0: m.shapeCx - m.shapeW / 2
            y0: m.bodyTop
            w: m.shapeW
            h: m.bodyH
            rTop: m.joined ? Theme.rLg : m.lerp(m.pillR, Theme.rLg, m.th)
            rBot: m.lerp(m.pillR, Theme.rLg, m.th)
            edgeY: m.barHt
            neck: m.neckR * (1 + 0.6 * m.wobble)
            fill: m.shapeFill
            ringScale: 0.5 + 0.5 * m.tw
            flip: m.flip
        }
        // The fill alone, in white, as the relief's mask (I168), redrawn only when the path changes.
        Shape {
            id: maskShape
            visible: reliefBox.on
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillColor: "white"
                PathSvg { path: reliefBox.on ? shape.fillPath : "" }
            }
        }
        ShaderEffectSource {
            id: shapeMask
            x: -100000
            width: parent.width
            height: parent.height
            sourceItem: reliefBox.on ? maskShape : null
            hideSource: true
            live: false
        }
        Connections {
            target: reliefBox.on ? shape : null
            function onFillPathChanged() { shapeMask.scheduleUpdate() }
        }
    }
    // K59/K61 (I168): the material over the shape's fill, the body carrying its sheet as it grows (as the Stage's).
    Item {
        id: reliefBox
        readonly property bool on: Theme.texShell && shape.visible && shape.w > 2 && shape.h > 2
        z: Theme.texText ? 2 : 0
        visible: on
        width: m.morphW
        height: m.morphH
        transform: Scale { yScale: m.flip ? -1 : 1; origin.y: m.morphH / 2 }
        Loader {
            anchors.fill: parent
            active: reliefBox.on
            sourceComponent: Relief {
                anchors.fill: parent
                mask: shapeMask
                carry: m.shapeCarry
                bandEdge: m.joined ? shape.hy0 + shape.hh : shape.edgeY
                bandWeight: m.joined ? 1 : Theme.panel.a
            }
        }
    }
    // The island's face in the shape's head, where the pill was (only while this shape holds the island).
    CompactFace {
        id: headFace
        active: m.shown && m.morph && m.holds
        visible: active
        face: m.pillGeom ? (m.pillGeom.face || "clock") : "clock"
        animate: m.shown
        x: Math.round((m.joined ? m.pillCx : m.shapeCx) - width / 2)
        y: m.flip ? m.morphH - m.pillTop - m.pillH : m.pillTop
        width: Math.max(m.pillW, wantW + 2 * Theme.pad)
        height: m.pillH
    }

    // ---- the card: where the grown shape stands (morph), or the sliding card (fallback). The content is cut to the shape.
    Item {
        id: card
        visible: m.shown
        width: m.cardW
        height: m.cardH
        x: m.morph ? Math.round((m.morphW - width) / 2) : m.shade
        y: m.morph ? (m.flip ? m.morphH - m.cardTop - height : m.cardTop) : m.shade - m.slide * (1 - m.p)
        opacity: m.morph ? m.contentP : Math.min(1, m.p * 1.6)
        scale: m.morph ? 0.98 + 0.02 * m.contentP : m.slideScale + (1 - m.slideScale) * m.p
        transformOrigin: m.flip ? Item.Bottom : Item.Top
        Item {
            id: reveal
            readonly property real shapeTop: m.flip ? m.morphH - m.bodyTop - m.bodyH : m.bodyTop
            readonly property real cutTop: m.morph ? Math.max(0, Math.min(card.height, shapeTop - card.y)) : 0
            readonly property real cutBottom: m.morph
                ? Math.max(cutTop, Math.min(card.height, shapeTop + m.bodyH - card.y)) : card.height
            readonly property real cutLeft: m.morph
                ? Math.max(0, Math.min(card.width, m.shapeCx - m.shapeW / 2 - card.x)) : 0
            readonly property real cutRight: m.morph
                ? Math.max(cutLeft, Math.min(card.width, m.shapeCx + m.shapeW / 2 - card.x)) : card.width
            x: cutLeft
            y: cutTop
            width: cutRight - cutLeft
            height: cutBottom - cutTop
            clip: m.morph
            Item {
                id: inner
                x: -reveal.cutLeft
                y: -reveal.cutTop
                width: card.width
                height: card.height
            }
        }
    }
}
