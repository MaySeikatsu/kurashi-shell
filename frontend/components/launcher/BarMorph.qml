import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../core"
import ".."
import "../island"
import "../decor"
import "../motion"
import "../../core/motion"

// One surface that grows out of the bar (W34, docs/ux/motion.md "the bar reaches out"): the launcher and the notification
// centre. The island's own machinery (Stage, W21/K42) — one MorphShape from the island pill's rect (IslandGeom) to the
// card's, the liquid neck at the bar's edge (strip) or the neck under the island's block (joined, keycap and soft chrome),
// the pill's face in the shape's head, the content cut to the shape and faded in late, out first — for a surface that is
// not the Stage. W36: its springs are the Stage's own (MorphSprings: the shape's centre, width and foot in px, each a
// spring from `motion.spring.*`; the travel and width lead on the way out, the foot on the way back; velocity kept across
// every retarget; the overshoot soft-limited, squash & stretch and the neck's wobble from `motion.spring.squash`), so the
// launcher and the centre move exactly as an island view does in every profile.
//
// The owner is a layer window that, while `layout` (the shape is out), anchors one bar edge only (the compositor centres it
// on its output, so the shape's box is centred on the bar: MorphShape opens the bar's rule from its own centre) with
// margin 0 on that edge, and takes this item's size: the window covers the bar's strip above the card only while the
// shape is out (K16; idle it keeps the card's size, or is unmapped). Its content goes in as children: they land in a
// `cardW` x `cardH` box where the grown card stands, cut to the shape while it moves. Without a top or bottom bar (`morph`
// false) the card slides in instead and the owner draws its own chrome (`morph` tells it which).
//
// While the shape is out it holds the island (IslandGeom.takenOn — set here imperatively, the Stage binds it: never both
// at once, and released only while it still names this output), so the bar hides its pill and opens its rule under the
// shape, and the shape's head shows the pill's face: one island on screen. A pill already held by the Stage is left alone
// (the shape then grows without a face). No pill on this output: the shape grows from the bar's centre.
// Theme.springOn false (motion none, reduce motion) cuts. Ma: nothing runs at rest; paths change only while it morphs.
Item {
    id: m

    // The output's name (IslandGeom's key), whether its bar is at the bottom (the shape mirrored), whether it is at the top
    // or bottom at all (else the slide).
    property string outName: ""
    // The surface class whose form it opens and closes in (K83: `launcher` or `centre`).
    property string surface: "launcher"
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
    // The card's corners at rest, for the owner's blur region (it must not reach past the outline): round away from the
    // bar, square where it grows out of it (the fillets beyond are the bar's); round all round in the fallback.
    readonly property real cardRNear: morph ? 0 : Theme.rLg
    readonly property real cardRFar: Theme.rLg

    // W53.5 (`[decor] surface.join = false`): the look keeps its cards apart from the bar (they slide in as blocks).
    readonly property bool morph: onBar && Theme.decor("surface.join", true) !== false
    // The look moves the sliding card in a form of its own (Entrance: slide, zoom, fade, flip): the slide here steps aside.
    readonly property bool formed: !morph && form.form !== "grow" && form.form !== "none"
    // On screen: opening, open or folding back.
    property bool shown: false
    property bool gate: false
    // The fallback's progress (0 hidden … 1 in), on today's curve — a Driver since K83 (row 655): scrubbed in tests too.
    readonly property real p: pDrv.value
    // The content's fade (late in, first out).
    property real contentP: 0
    // At rest open: the springs have arrived and the content is in (the owner turns its blur on only then: the shape
    // changes size every frame).
    readonly property bool settled: !morph ? (shown && p >= 1)
        : (shown && open && !gate && springs.settled && contentWanted && !run.busy)
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
    // Room round the card for the springs: the width's soft-limited overshoot and the landing's bulge (squash) on each
    // side, the centre's overshoot past its travel, the neck's fillets and the soft shadow.
    readonly property int slackX: 16 + Theme.softR + Math.ceil(cardW * (springs.cap + springs.squash) / 2 + Math.abs(pillDx) * springs.cap)
    readonly property int slackY: 40
    readonly property real morphW: 2 * Math.ceil(Math.max(cardW / 2 + neckR + slackX, Math.abs(pillDx) + pillW / 2 + 8))
    readonly property real morphH: Math.ceil(cardTop + cardH + Theme.shadowDy + slackY)

    // ---- the springs (MorphSprings, the Stage's): in this item's px (its box is centred on the bar), towards the card
    // while the surface is open and has shown its first frame, else towards the pill. They stay towards the card while the
    // content fades out (it leaves first), then fold.
    readonly property real pillCx: morphW / 2 + pillDx
    readonly property real cardCx: morphW / 2
    readonly property real closedFoot: pillTop + pillH
    readonly property real cardFoot: cardTop + cardH
    readonly property bool extended: shown && !gate && (open || contentP > 0.4)
    // K83 (W59.3, as the Stage): while a shape or sheet form moves the card the springs stand where it rests (the form
    // draws the shape) and take over once it is in; folding in a form they stand at the pill.
    readonly property bool formHolds: run.formed && (run.busy || !open)
    MorphSprings {
        id: springs
        on: Theme.springOn && m.shown && m.morph && !m.formHolds
        expanding: m.extended
        cxTo: m.extended ? m.cardCx : m.pillCx
        wTo: m.extended ? m.cardW : m.pillW
        hTo: m.extended ? m.cardFoot : m.closedFoot
    }
    // ---- K83 (W59.3): the form (SurfaceForm): `grow` and today's content forms keep the springs' morph; expand, iris,
    // stamp and outline draw the live shape from one progress; a sheet form runs the card-level FormHost below.
    SurfaceForm {
        id: run
        surface: m.surface
        want: m.open && m.shown && !m.gate && m.morph
        hold: !springs.settled
        fromCx: m.pillCx
        fromW: m.pillW
        fromTop: m.pillTop
        fromFoot: m.closedFoot
        fromR: m.pillR
        toCx: m.cardCx
        toW: m.cardW
        toTop: m.cardTop
        toFoot: m.cardFoot
        toR: Theme.rLg
        edgeY: m.barHt
        onLanded: at => { if (at <= 0 && !m.open && m.shown) { m.release(); handBack.start() } }
    }
    readonly property bool useForm: run.mode === "shape" && run.busy && run.shape !== null
    readonly property QtObject sf: useForm ? run.shape : null
    readonly property real lift: sf ? sf.lift : 0
    onShownChanged: if (!shown) run.reset()
    // This shape holds the island (see the header).
    property bool holds: false
    function take() {
        if (outName !== "" && IslandGeom.takenOn === "" && !cardHost.sheetSolid) { IslandGeom.takenOn = outName; holds = true }
    }
    function release() {
        if (holds && IslandGeom.takenOn === outName) IslandGeom.takenOn = ""
        holds = false
    }
    Component.onDestruction: release()
    // K83 (row 656): while a sheet form warps the card the bar keeps its pill (the head gives way with the shape).
    Connections {
        target: cardHost
        function onSheetSolidChanged() {
            if (cardHost.sheetSolid) m.release()
            else if (m.shown && m.open && !m.gate) m.take()
        }
    }

    // Test only (KURASHI_MORPH_DEBUG=1): when the growth starts, and the springs twice a second while the shape is out.
    readonly property bool debugLog: Quickshell.env("KURASHI_MORPH_DEBUG") === "1"
    property double openedAt: 0
    Timer {
        interval: 500
        repeat: true
        running: m.debugLog && m.shown
        onTriggered: console.log("bar-morph cx=" + springs.cx.toFixed(1) + " w=" + springs.w.toFixed(1) + " h=" + springs.h.toFixed(1)
            + " to=" + springs.cxTo.toFixed(1) + "," + springs.wTo.toFixed(1) + "," + springs.hTo.toFixed(1)
            + " content=" + m.contentP.toFixed(2) + " open=" + m.open + " gate=" + m.gate + " holds=" + m.holds
            + " card=" + m.cardW + "x" + m.cardH)
    }
    Connections {
        target: m.debugLog && m.shown ? m.Window.window : null
        function onFrameSwapped() {
            var t = Date.now() - m.openedAt
            if (t < 900) console.log("bar-morph frame +" + t + " ms w=" + springs.w.toFixed(1) + " h=" + springs.h.toFixed(1))
        }
    }
    onOpenChanged: { openedAt = Date.now(); follow() }
    function follow() {
        if (open) {
            pillGeom = IslandGeom.pillOf(outName)
            handBack.stop()
            if (morph) {
                // The shape starts as the pill (no spring yet) and grows from the first presented frame on; reopened while
                // it folds back, it grows again from where it is, with its velocity (the targets move, MorphSprings).
                if (!shown) { gate = true; shown = true; springs.place(pillCx, pillW, closedFoot) }
            } else {
                if (!shown) { pDrv.snap(0); gate = true; shown = true }
                else runP(1)
            }
        } else if (shown) {
            gate = false
            reached = false
            if (morph) Qt.callLater(checkFolded)
            else runP(0)
        }
    }
    // The bar moved while the card is out: no morph across edges, the card goes and comes back in the new manner.
    onMorphChanged: if (shown) {
        handBack.stop(); release()
        shown = false; gate = false; pDrv.snap(0)
        springs.snap()
        if (open) follow(); else m.hidden()
    }
    // W53.5: a stepped look (`motion.kind = stepped`) moves on its own staircases and times: opening on the open curve,
    // folding on the close one (K74's enter curve otherwise).
    readonly property bool stepped: Theme.motionKind === "stepped"
    readonly property var enterCurve: ({ kind: "cubic", ms: Theme.stdMs, points: Theme.enterCurve })
    Driver {
        id: pDrv
        curves: m.stepped ? ({ open: { kind: "cubic", ms: Theme.openMs, points: Theme.openCurve },
                               close: { kind: "cubic", ms: Theme.closeMs, points: Theme.closeCurve } })
            : ({ open: m.enterCurve, close: m.enterCurve })
        keepVelocity: false
        onLanded: if (m.p <= 0 && !m.open) { m.shown = false; m.hidden() }
    }
    function runP(t) { if (pDrv.to !== t) pDrv.to = t; else pDrv.go() }
    // The growth starts on the first presented frame (the window is mapped and sized by then), not on the request. The
    // start is read again then: the pill may have been reported after the request.
    Connections {
        target: m.gate ? m.Window.window : null
        function onFrameSwapped() {
            if (!m.gate) return
            if (m.morph) springs.place(m.pillCx, m.pillW, m.closedFoot)
            m.gate = false
            if (m.debugLog) console.log("bar-morph gate " + m.outName + " +" + (Date.now() - m.openedAt) + " ms")
            if (m.morph) m.take()
            else m.runP(1)
        }
    }
    // Folded back: the pill goes back to the bar first and the shape a moment later, so the screen never shows no island.
    Connections {
        target: springs
        function onHChanged() { m.checkFolded() }
        function onWChanged() { m.checkFolded() }
    }
    function checkFolded() {
        if (open || !shown || !morph || handBack.running || Math.abs(springs.hTo - closedFoot) > 0.5) return
        if (run.formed && (run.busy || run.p > 0)) return   // (a form folding the card ends it itself: run.landed)
        if (Math.abs(springs.h - springs.hTo) <= 1.5 && Math.abs(springs.w - springs.wTo) <= 3) { release(); handBack.start() }
    }
    Timer {
        id: handBack
        interval: 80
        onTriggered: {
            if (m.open) return
            m.shown = false
            m.hidden()
        }
    }

    // ---- the shape's geometry, in a top bar's frame (the box is mirrored for a bottom bar), as the Stage's head mode.
    function lerp(a, b, t) { return a + (b - a) * t }
    function clamp01(v) { return Math.max(0, Math.min(1, v)) }
    // How far the shape has grown out of the pill, 0..1 (the foot against the card's): corners, tint and ring follow it.
    // (a shape form: its own `grow`, and `tint` for fill, corners and ring)
    readonly property real tgrow: sf ? sf.grow : clamp01((springs.h - closedFoot) / Math.max(1, cardFoot - closedFoot))
    readonly property real ttint: sf ? sf.tint : tgrow
    // The drawn shape: squash & stretch narrows it while its foot moves fast, and it bulges as it lands (I113); a shape
    // form's scale is about the bar's edge (the hinge).
    readonly property real shapeW: sf ? Math.max(0, sf.w * sf.sx) : Math.max(0, springs.wOut * (1 - springs.squeeze))
    readonly property real shapeCx: sf ? sf.cx : springs.cxOut
    readonly property real shapeFoot: sf ? barHt + (sf.foot - barHt) * sf.sy : springs.hOut
    readonly property real pillR: Math.min(Theme.rFull, pillH / 2)
    // The body: the whole shape on a strip (the head is its top); joined, what grows out from under the island's block.
    readonly property real bodyTop0: joined ? lerp(closedFoot, cardTop, tgrow) : pillTop
    readonly property real bodyTop: sf && bodyTop0 > barHt ? barHt + (bodyTop0 - barHt) * sf.sy : bodyTop0
    readonly property real bodyH: Math.max(0, shapeFoot - bodyTop)
    readonly property point shapeCarry: Qt.point(shapeCx - cardCx, (flip ? -1 : 1) * (shapeFoot - cardFoot))
    readonly property color shapeFill: {
        // (I277: the card is the sheet it grows out of — the bar's surface colour, not the container's)
        var c = Qt.tint(boxed ? Theme.surface : Theme.containerHigh, Qt.alpha(Theme.surface, ttint))
        return Qt.alpha(c, Theme.panel.a)
    }
    // I160 (as the Stage): the head over the bar's translucent strip is made one layer with it as the card grows.
    readonly property real stripA: Theme.surfaceAlpha.a
    readonly property real headA: stripA >= 0.999 ? Theme.panel.a : Math.max(0, (Theme.panel.a - stripA) / (1 - stripA))
    readonly property color headFill: Qt.alpha(shapeFill, lerp(Theme.panel.a, headA, ttint))
    // The content comes in once the shape has nearly grown (fade + 0.98 → 1, ≤ 160 ms) and leaves first (90 ms); once in it
    // stays while the card only grows or shrinks a little (a list filling): `reached` latches until the surface closes.
    readonly property bool near: Math.abs(springs.hTo - cardFoot) < 1 && Math.abs(springs.wTo - cardW) < 1 && springs.pw > 0.92
        && springs.ph > 0.6 && (springs.pcx > 0.97 || Math.abs(springs.cx - springs.cxTo) < 16)
    property bool reached: false
    onNearChanged: if (near && open && shown && !gate) reached = true
    onGateChanged: reached = false
    readonly property bool contentWanted: morph ? (open && shown && !gate && (reached || near)) : true
    onContentWantedChanged: contentP = contentWanted ? 1 : 0
    // (a shape form shows the content itself: no fade after it)
    Behavior on contentP {
        enabled: m.morph && m.shown && Theme.quickMs > 0 && !run.formed
        NumberAnimation { duration: m.contentWanted ? 160 : 90; easing.type: Easing.OutCubic }
    }

    // The box the blur stands behind (I295, I296), in this item's coordinates and on screen's orientation: the body as
    // drawn while it morphs (it follows the springs every frame, so the blur never stands ahead of the shape), the card as
    // it slides otherwise. Owners build their window's BackgroundEffect region from it.
    // (K83: off while a shape form fades the card in, draws only its outline, or opens an iris — a box of blur would
    // stand outside it; it returns as the card stands)
    readonly property bool blurOn: shown && !cardHost.sheetBlurOff
        && (morph ? shapeW > 2 && bodyH > 2 && (!sf || (sf.below >= 0.999 && sf.irisR < 0)) : p > 0)
    readonly property real blurX: morph ? shapeCx - shapeW / 2 : shade
    readonly property real blurY: morph ? (flip ? morphH - bodyTop - bodyH : bodyTop) : shade - (formed ? 0 : slide * (1 - p))
    readonly property real blurW: morph ? shapeW : cardW
    readonly property real blurH: morph ? bodyH : cardH
    readonly property real blurRTop: morph ? (flip ? shape.rBot : shape.rTop) : (flip ? cardRFar : cardRNear)
    readonly property real blurRBottom: morph ? (flip ? shape.rTop : shape.rBot) : (flip ? cardRNear : cardRFar)

    // The bar's strip and the slack only while the shape is out (K16); idle, the card's size (the owner's window keeps no strip).
    readonly property bool layout: morph && shown
    width: layout ? morphW : cardW + 2 * shade
    height: layout ? morphH : cardH + 2 * shade

    // ---- K83 (W59.3): the card-level form host — the whole card as drawn (shape, material, head and face, content) in one
    // item, so a sheet form (W59.4) captures all of it while it moves; progress 1 (identity) unless a sheet form is
    // latched. `formLayer` draws through the shape forms' mask while one moves (FormMask: a layer only then).
    FormHost {
        id: cardHost
        surface: m.surface
        width: m.width
        height: m.height
        edge: m.flip ? "bottom" : "top"
        origin: Qt.rect(m.pillCx - m.pillW / 2, m.flip ? m.morphH - m.closedFoot : m.pillTop, m.pillW, m.pillH)
        direction: run.dir
        progress: run.sheet ? run.p : 1
        // (the card itself, its own fill drawn while a sheet warps it; the shape under it gives way: row 656)
        source: card
        visible: !run.sheet || run.p > 0
    Item {
        id: formLayer
        width: m.width
        height: m.height
        layer.enabled: run.masked && m.morph
        layer.effect: FormMask {
            form: run.shape
            keep: m.barHt - (Theme.outlineW > 0 || m.joined ? 0 : 1)
            flipped: m.flip
        }

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
            opacity: cardHost.sheetShadow
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
            neckF: Theme.rLg / 2
            neckScale: m.sf ? 1 : springs.neckScale
            x0: m.shapeCx - m.shapeW / 2
            y0: m.bodyTop
            w: m.shapeW
            h: m.bodyH
            rTop: m.joined ? Theme.rLg : m.lerp(m.pillR, Theme.rLg, m.ttint)
            rBot: m.lerp(m.pillR, Theme.rLg, m.ttint)
            edgeY: m.barHt
            neck: m.neckR
            fill: m.shapeFill
            headFill: m.headFill
            ringScale: 0.5 + 0.5 * m.ttint
            flip: m.flip
            fade: cardHost.sheetFillets
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
        opacity: cardHost.sheetFillets
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
        active: m.shown && m.morph && m.holds && !cardHost.sheetSolid
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
        y: m.morph ? (m.flip ? m.morphH - m.cardTop - height : m.cardTop) : m.shade - (m.formed ? 0 : m.slide * (1 - m.p))
        opacity: m.morph ? (m.sf ? m.sf.content : m.contentP) : (m.formed ? 1 : Math.min(1, m.p * 1.6))
        scale: m.morph ? (m.sf ? 1 : 0.98 + 0.02 * m.contentP) : (m.formed ? 1 : m.slideScale + (1 - m.slideScale) * m.p)
        transformOrigin: m.flip ? Item.Bottom : Item.Top
        // K83 (row 656): the card's own fill and outline while a sheet form captures it (the shape gives way).
        Rectangle {
            visible: m.morph && cardHost.sheetSolid
            anchors.fill: parent
            radius: Theme.rLg
            color: Theme.surface
            border.width: Theme.outlineW > 0 ? Theme.outlineW : 1
            border.color: Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline
        }
        // K83 (stamp): the card scales with its shape about the bar's edge.
        transform: Scale {
            origin.x: m.shapeCx - card.x
            origin.y: (m.flip ? m.morphH - m.barHt : m.barHt) - card.y
            xScale: m.sf ? m.sf.sx : 1
            yScale: m.sf ? m.sf.sy : 1
        }
        Item {
            id: reveal
            readonly property real shapeTop: m.flip ? m.morphH - m.bodyTop - m.bodyH : m.bodyTop
            // (a stamp scales the card with its shape instead of cutting it)
            readonly property bool cuts: m.morph && (!m.sf || m.sf.clipsContent)
            readonly property real cutTop: cuts ? Math.max(0, Math.min(card.height, shapeTop - card.y)) : 0
            readonly property real cutBottom: cuts
                ? Math.max(cutTop, Math.min(card.height, shapeTop + m.bodyH - card.y)) : card.height
            readonly property real cutLeft: cuts
                ? Math.max(0, Math.min(card.width, m.shapeCx - m.shapeW / 2 - card.x)) : 0
            readonly property real cutRight: cuts
                ? Math.max(cutLeft, Math.min(card.width, m.shapeCx + m.shapeW / 2 - card.x)) : card.width
            x: cutLeft
            y: cutTop
            width: cutRight - cutLeft
            height: cutBottom - cutTop
            clip: cuts
            // The look's form (W53, row 591; decor/Entrance): sliding in, the content arrives as the look moves (slide,
            // zoom, fade, flip) on the card's own progress; `grow` (K74's, the default) leaves it to the slide above. The
            // morph is the shape's own motion: the form stays out of it.
            Entrance {
                id: form
                x: -reveal.cutLeft
                y: -reveal.cutTop
                width: card.width
                height: card.height
                surface: m.surface
                progress: m.morph ? 1 : m.p
                edge: m.flip ? "bottom" : "top"
                Item {
                    id: inner
                    width: card.width
                    height: card.height
                }
            }
        }
    }
    }
    }
    // K83 (outline): the stepped outline rects while the outline form moves the card (outside the masked layer).
    OutlineRects {
        width: m.morphW
        height: m.morphH
        rects: m.sf && m.sf.outline ? m.sf.rects : []
        transform: Scale { yScale: m.flip ? -1 : 1; origin.y: m.morphH / 2 }
    }
}
