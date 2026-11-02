import QtQuick
import "../../core"
import "../../core/motion"
import ".."

// The Motion page's preview stage (W59.6b; brief docs/ux/motion-engine.md §8 item 1, §10, §11): a miniature bar over a
// patterned ground with a button per surface class. A button (click, Space or Return) opens that class's sample card and
// closes it again, through the shell's own FormHost and forms (linked from frontend/components/motion, as the recipe list
// does) on a Driver fed the profile's curves — the frames the shell draws, with the settings in effect now
// (`Theme.motionForm`, `Theme.motionCurves`, the accents). Under reduce motion that is what runs: short fades.
//   Speed 1× · ½× · ¼×  stretches this Driver's curves only (never the speed setting);
//   the scrubber        holds the card at any p (Driver.track); a drag lets go on release (Driver.release), the arrow keys
//                       hold the frame until Return;
//   Compare (hold)      plays the motion as it was before the last motion change (a snapshot the stage keeps), and on
//                       release the one in effect.
// It plays when a motion setting changes and when asked; it never loops. Ma: at rest nothing runs, and no layer exists (a
// sheet form's layer lives only while 0 < p < 1); while the window is not visible it stands still at the nearest rest;
// leaving the page destroys it (the page's Loader).
RoundBox {
    id: pv
    objectName: "motion-preview"
    implicitHeight: col.implicitHeight + 2 * Theme.pad
    radius: Theme.rSm
    color: Theme.container
    border.width: 1
    border.color: Theme.outline
    Accessible.role: Accessible.Grouping
    Accessible.name: I18n.tr("motion.ui.preview.title")

    readonly property var surfaces: ["island", "panel", "peek", "launcher", "centre", "toast", "sidebar", "dock", "bar",
                                     "osd", "menu", "dialog"]
    // Peeks, on-screen displays and menus move on the quick-moves curve (brief §6); every other class opens on Opens and
    // closes on Closes.
    function roleOf(s) { return s === "peek" || s === "osd" || s === "menu" ? "fast" : "auto" }

    // --- the gate (Ma) ---
    // Shown: the window is up (a Settings window that goes away ends the app; a minimised or hidden one stands still).
    readonly property var win: pv.Window.window
    readonly property bool shown: !!pv.win && pv.win.visible && pv.win.visibility !== Window.Minimized
        && pv.win.visibility !== Window.Hidden
    onShownChanged: if (!shown) pv.rest()

    // --- what the stage shows ---
    property string surface: "panel"
    // The card's rest: open (p = 1) or closed (p = 0).
    property bool open: false
    // The direction of the last transition played ("open" | "close"): Compare replays it.
    property string lastDir: "open"
    property real speed: 1
    property bool comparing: false
    readonly property bool reduce: { Store.config; return Store.valueOf("a11y.reduce_motion", "") === true }

    // --- the motion in effect, and the one before the last change (Compare) ---
    function take() {
        var forms = {}
        pv.surfaces.forEach(function (s) {
            forms[s] = { open: Theme.motionForm(s, "open"), close: Theme.motionForm(s, "close") }
        })
        return {
            curves: JSON.parse(JSON.stringify(Theme.motionCurves)),
            forms: forms,
            accents: {
                squash: Number(Theme.motionAccent("squash")) || 0, jelly: Number(Theme.motionAccent("jelly")) || 0,
                content: String(Theme.motionAccent("content") || "late"), stagger: Number(Theme.motionAccent("stagger_ms")) || 0
            }
        }
    }
    property var now: null
    property var prev: null
    // What the last motion change touched: {surface, dir} for a form, {role} for a curve, {} for the rest.
    property var what: ({})
    // (before the theme document arrives there is nothing to remember: its arrival is no change)
    readonly property bool hasTokens: { var t = Theme.tokens; for (var k in t) return true; return false }
    Component.onCompleted: if (pv.hasTokens) pv.now = pv.take()
    Connections {
        target: Theme
        function onTokensChanged() { Qt.callLater(pv.noteTokens) }
    }
    function noteTokens() {
        if (!pv.hasTokens) return
        var next = pv.take()
        if (pv.now && JSON.stringify(next) === JSON.stringify(pv.now)) return
        var old = pv.now
        pv.now = next
        if (!old) return
        pv.prev = old
        // The one surface and direction whose form changed (a profile changes many: the stage keeps its surface).
        var changedForms = []
        pv.surfaces.forEach(function (s) {
            ["open", "close"].forEach(function (d) { if (old.forms[s][d] !== next.forms[s][d]) changedForms.push({ surface: s, dir: d }) })
        })
        var roles = ["open", "close", "fast", "effects"].filter(function (r) {
            return JSON.stringify(old.curves[r]) !== JSON.stringify(next.curves[r])
        })
        if (changedForms.length === 1) pv.what = changedForms[0]
        else if (changedForms.length === 0 && roles.length === 1) pv.what = { role: roles[0] }
        else pv.what = {}
        if (pv.comparing) return
        // Plays on change: the surface whose form changed, the way it changed; a curve's own direction; else open.
        var s = pv.what.surface || pv.surface
        var dir = pv.what.dir || (pv.what.role === "close" ? "close" : "open")
        pv.play(s, dir)
    }
    // Compare may not play a previous form that turns or flashes while reduce motion is on (brief §11).
    function harsh(form) {
        var m = Theme.formMeta(form)
        var fl = m && m.flags ? Array.prototype.slice.call(m.flags) : []
        return fl.indexOf("vestibular") >= 0 || fl.indexOf("flash") >= 0
    }
    readonly property bool compareBlocked: !!pv.prev && pv.reduce
        && (pv.harsh(pv.prev.forms[pv.surface].open) || pv.harsh(pv.prev.forms[pv.surface].close))
    readonly property bool canCompare: !!pv.prev && !pv.compareBlocked
    // The snapshot the stage runs now.
    readonly property var running: pv.comparing && pv.prev ? pv.prev : pv.now

    // The curves at the stage's speed: a timed curve's duration and a spring's response stretch; spring_q's constants
    // (K42's 16-ms integrator) slow by s² and s, which runs it s times slower.
    function stretched(c, f) {
        if (!c || f === 1) return c
        var o = Object.assign({}, c)
        if (c.kind === "spring_q") { o.spring = c.spring / (f * f); o.damping = c.damping / f }
        else {
            if (c.ms) o.ms = c.ms * f
            if (c.kind === "spring") o.response = (c.response || c.ms || 0) * f
        }
        return o
    }
    readonly property var runCurves: {
        var cs = pv.running ? pv.running.curves : Theme.motionCurves
        var f = 1 / pv.speed, out = {}
        for (var r in cs) out[r] = pv.stretched(cs[r], f)
        return out
    }
    function formFor(s, dir) { return pv.running ? pv.running.forms[s][dir] : Theme.motionForm(s, dir) }

    // --- playing ---
    // Open or close a class's sample card from its rest (dir "open" | "close"; the card goes there from the other end).
    function play(s, dir) {
        if (!pv.shown) return
        pv.select(s)
        pv.place()
        pv.lastDir = dir
        var from = dir === "open" ? 0 : 1
        drv.snap(from)
        drv.to = from
        pv.open = dir === "open"
        // `none` is a cut: no frames between the rests.
        if (pv.formFor(s, dir) === "none") { drv.snap(1 - from); drv.to = 1 - from; return }
        drv.to = 1 - from
    }
    // A class's button: open its card, or close it when it is the one open.
    function toggle(s) { pv.play(s, s === pv.surface && pv.open ? "close" : "open") }
    function replay() { pv.play(pv.surface, pv.lastDir) }
    // Stand still at the nearest rest (window hidden): nothing runs, the sheet's layer goes.
    function rest() {
        var at = drv.value >= 0.5 ? 1 : 0
        drv.snap(at)
        drv.to = at
        pv.open = at === 1
        pv.comparing = false
    }
    // Compare: pressed, the previous motion plays; let go, the motion in effect plays.
    function compare(on) {
        if (on === pv.comparing) return
        if (on && !pv.canCompare) return
        pv.comparing = on
        pv.play(pv.surface, pv.lastDir)
    }
    // The scrubber: hold the card at p of an opening (0 → 1); `release` lets it go to the nearer rest.
    function scrubTo(p) {
        if (!pv.shown) return
        if (!drv.tracking) {
            pv.place()
            // (from the closed rest, so the frame is an opening's, as the shell's scrubbed frame is)
            if (host.lastRest !== 0) { drv.snap(0); drv.to = 0 }
            pv.lastDir = "open"
        }
        drv.track(Math.max(0, Math.min(1, p)), 0, 1)
    }
    function letGo(v) { if (drv.tracking) drv.release(v) }

    Driver {
        id: drv
        curves: pv.runCurves
        role: pv.roleOf(pv.surface)
        onLanded: at => { drv.to = at; pv.open = at >= 1 }
    }

    // The bar's order: modules left of the island, the island in the middle, modules right of it.
    readonly property var barLeft: ["launcher", "sidebar", "menu", "peek"]
    readonly property var barRight: ["panel", "centre", "toast", "osd", "dock", "bar", "dialog"]
    readonly property var barOrder: pv.barLeft.concat(["island"], pv.barRight)
    function chipOf(s) {
        if (s === "island") return islandChip
        var i = pv.barLeft.indexOf(s)
        if (i >= 0) return leftChips.itemAt(i)
        i = pv.barRight.indexOf(s)
        return i >= 0 ? rightChips.itemAt(i) : null
    }
    component Chip: RoundBox {
        id: chip
        required property string modelData
        readonly property bool shownHere: pv.surface === modelData
        readonly property bool on: shownHere && pv.open
        readonly property bool pill: modelData === "island"
        objectName: "preview-class:" + modelData
        // The island is the pill in the bar's middle; the rest are its modules.
        width: lbl.implicitWidth + (pill ? 22 : 12)
        height: pv.barH - 8
        y: 4
        radius: pill ? height / 2 : Theme.rSm
        color: chip.on ? Theme.selected : pill || hov.hovered ? Theme.containerHigh : "transparent"
        border.width: pill ? 1 : 0
        border.color: Theme.outline
        activeFocusOnTab: chip.shownHere
        Accessible.role: Accessible.Button
        Accessible.name: I18n.tr("motion.surface." + chip.modelData)
        Accessible.description: I18n.tr(chip.on ? "motion.ui.preview.class_close" : "motion.ui.preview.class_open")
        Accessible.checkable: true
        Accessible.checked: chip.on
        Keys.onSpacePressed: event => { pv.toggle(chip.modelData); event.accepted = true }
        Keys.onReturnPressed: event => { pv.toggle(chip.modelData); event.accepted = true }
        Keys.onEnterPressed: event => { pv.toggle(chip.modelData); event.accepted = true }
        Keys.onLeftPressed: event => { pv.moveChip(pv.barOrder.indexOf(chip.modelData) - 1); event.accepted = true }
        Keys.onRightPressed: event => { pv.moveChip(pv.barOrder.indexOf(chip.modelData) + 1); event.accepted = true }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Home) { pv.moveChip(0); event.accepted = true }
            else if (event.key === Qt.Key_End) { pv.moveChip(pv.barOrder.length - 1); event.accepted = true }
        }
        Text {
            id: lbl
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            anchors.centerIn: parent
            color: chip.on ? Theme.fgOnSelected : Theme.fg
            font.pixelSize: Theme.fs - 2
            font.weight: chip.shownHere ? Font.DemiBold : Font.Normal
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("motion.ui.preview.class." + chip.modelData)
        }
        // The class shown (closed or scrubbed) is marked under its name, not by colour alone.
        Rectangle {
            visible: chip.shownHere && !chip.on
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: lbl.implicitWidth
            height: 2
            color: Theme.accent
        }
        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        MouseArea { anchors.fill: parent; onClicked: pv.toggle(chip.modelData) }
        FocusRing { anchors.fill: parent; shown: chip.activeFocus; corner: chip.radius }
    }

    // --- the stage's geometry (stage coordinates) ---
    readonly property int barH: 30
    // The pressed button's rect for the classes that come out of the bar, and where each card hangs.
    property var geo: ({ x: 0, y: 0, w: 10, h: 10, edge: "top", o: Qt.rect(0, 0, 0, 0) })
    function chipRect(s) {
        var c = pv.chipOf(s)
        if (!c) return Qt.rect(stage.width / 2 - 20, 4, 40, pv.barH - 8)
        var m = c.mapToItem(stage, 0, 0)
        return Qt.rect(m.x, m.y, c.width, c.height)
    }
    function place() {
        var W = stage.width, H = stage.height, B = pv.barH, s = pv.surface
        var c = pv.chipRect(s), cx = c.x + c.width / 2
        var g
        var under = function (w, h) {
            var x = Math.max(8, Math.min(W - w - 8, cx - w / 2))
            return { x: x, y: B, w: w, h: h, edge: "top" }
        }
        switch (s) {
        case "island": g = under(Math.min(300, W - 16), 124); break
        case "panel": g = under(240, 136); break
        case "peek": g = under(200, 38); break
        case "launcher": g = under(260, 152); break
        case "centre": g = { x: W - 8 - 220, y: B, w: 220, h: H - B - 8, edge: "top" }; break
        case "toast": g = { x: W - 8 - 220, y: B + 8, w: 220, h: 56, edge: "right" }; break
        case "sidebar": g = { x: 0, y: B, w: 170, h: H - B, edge: "left" }; break
        case "dock": g = { x: (W - 220) / 2, y: H - 46 - 104, w: 220, h: 96, edge: "bottom" }; break
        case "bar": g = { x: 24, y: H - 8 - 26, w: W - 48, h: 26, edge: "bottom" }; break
        case "osd": g = { x: (W - 200) / 2, y: H - 16 - 40, w: 200, h: 40, edge: "bottom" }; break
        case "menu": g = under(150, 104); break
        case "dialog": g = { x: (W - 280) / 2, y: B + (H - B - 124) / 2, w: 280, h: 124, edge: "top" }; break
        default: g = under(240, 136)
        }
        // The origin in the card's own coordinates: the pressed button (cards out of the bar), the dock's icon, else none.
        var o = Qt.rect(0, 0, 0, 0)
        if (g.edge === "top" && s !== "dialog") o = Qt.rect(c.x - g.x, c.y - g.y, c.width, c.height)
        else if (s === "dock") o = Qt.rect(g.w / 2 - 14, g.h + 10, 28, 28)
        g.o = o
        pv.geo = g
    }
    onWidthChanged: Qt.callLater(pv.place)

    // --- what the line under the stage says ---
    function formName(f) {
        return I18n.has("config.choice.motion.form." + f) ? I18n.tr("config.choice.motion.form." + f) : f
    }
    readonly property string stateText: {
        var name = I18n.tr("motion.ui.preview.class." + pv.surface)
        if (drv.tracking) return I18n.fmt("motion.ui.preview.state.scrub", { surface: name, p: drv.value.toFixed(2) })
        var dir = drv.running ? drv.direction : pv.lastDir
        var form = pv.formFor(pv.surface, dir)
        var c = pv.running ? pv.running.curves[pv.roleOf(pv.surface) === "fast" ? "fast" : dir] : null
        if (form === "none" || (c && c.kind === "none"))
            return I18n.fmt("motion.ui.preview.state.cut", { surface: name })
        var key = "motion.ui.preview.state." + dir + (c && c.ms > 0 && c.kind !== "spring_q" ? "_ms" : "")
        return I18n.fmt(key, { surface: name, form: pv.formName(form), ms: c ? Math.round(c.ms) : 0 })
    }

    Column {
        id: col
        x: Theme.pad
        y: Theme.pad
        width: parent.width - 2 * Theme.pad
        spacing: Theme.gap

        // The title and the help line.
        Row {
            width: parent.width
            spacing: Theme.gap
            MotionText { id: ttl; font.weight: Font.DemiBold; text: I18n.tr("motion.ui.preview.title") }
            MotionText {
                anchors.baseline: ttl.baseline
                width: parent.width - ttl.width - Theme.gap
                small: true
                color: Theme.dim
                text: I18n.tr("motion.ui.preview.help")
            }
        }

        // --- the stage: a ground with a pattern (so a translucent card, a blur or a fade reads), the bar, the card ---
        Item {
            id: stage
            objectName: "preview-stage"
            width: parent.width
            height: 214
            clip: true
            Accessible.role: Accessible.Animation
            Accessible.name: pv.stateText

            Canvas {
                id: ground
                anchors.fill: parent
                renderStrategy: Canvas.Cooperative
                // Painted once per size and colours (no animation: Ma).
                property color a: Theme.containerHigh
                property color b: Theme.outline
                onAChanged: requestPaint()
                onBChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.fillStyle = a
                    ctx.fillRect(0, 0, width, height)
                    ctx.strokeStyle = Qt.rgba(b.r, b.g, b.b, 0.55)
                    ctx.lineWidth = 6
                    for (var x = -height; x < width; x += 22) {
                        ctx.beginPath(); ctx.moveTo(x, height); ctx.lineTo(x + height, 0); ctx.stroke()
                    }
                    // A few dots on the stripes: a moving edge or a blur shows against them.
                    ctx.fillStyle = Qt.rgba(b.r, b.g, b.b, 0.9)
                    for (var gx = 11; gx < width; gx += 44)
                        for (var gy = 11; gy < height; gy += 44) { ctx.beginPath(); ctx.arc(gx, gy, 2.5, 0, 2 * Math.PI); ctx.fill() }
                }
            }

            // The dock (under its card) and a bottom bar's place: drawn only for those classes, as their stage.
            RoundBox {
                visible: pv.surface === "dock"
                x: (stage.width - 160) / 2
                y: stage.height - 44
                width: 160
                height: 36
                radius: 10
                color: Theme.surface
                border.width: 1
                border.color: Theme.outline
                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Repeater {
                        model: 4
                        Rectangle { width: 22; height: 22; radius: 6; color: index === 2 ? Theme.accent : Theme.containerHigh }
                    }
                }
            }

            // --- the sample card ---
            Item {
                id: place
                objectName: "preview-card"
                x: pv.geo.x
                y: pv.geo.y
                width: pv.geo.w
                height: pv.geo.h
                // Closed: nothing drawn (brief §10).
                visible: drv.value > 0 || drv.running
                // The accents (squash, jelly) about the card's hinge, from this stage's motion.
                transform: accents.scale
                Accents {
                    id: accents
                    target: place
                    edge: pv.geo.edge
                    velocity: drv.velocity
                    progress: drv.value
                    moving: drv.running
                    squash: pv.running ? pv.running.accents.squash : 0
                    jelly: pv.running && !pv.reduce ? pv.running.accents.jelly : 0
                }
                // A shape form without a drawing of its own (grow: the pill grows into the card) is the surface's morph on
                // the shell: here a silhouette from the pressed button (or the edge) to the card, clipping it.
                readonly property bool morph: host.family === "shape" && host.transformComp === "" && host.form !== "none"
                readonly property real m: morph ? host.progress : 1
                readonly property rect from: {
                    var o = pv.geo.o
                    if (o.width > 0) return o
                    var e = pv.geo.edge, w = place.width, h = place.height
                    return e === "left" ? Qt.rect(0, 0, 0, h) : e === "right" ? Qt.rect(w, 0, 0, h)
                        : e === "bottom" ? Qt.rect(0, h, w, 0) : Qt.rect(0, 0, w, 0)
                }
                Item {
                    id: sil
                    x: place.from.x * (1 - place.m)
                    y: place.from.y * (1 - place.m)
                    width: Math.max(0, place.from.width + (place.width - place.from.width) * place.m)
                    height: Math.max(0, place.from.height + (place.height - place.from.height) * place.m)
                    clip: place.morph && host.busy
                    FormHost {
                        id: host
                        objectName: "preview-host"
                        x: -sil.x
                        y: -sil.y
                        width: place.width
                        height: place.height
                        surface: pv.surface
                        edge: pv.geo.edge
                        origin: pv.geo.o
                        progress: drv.value
                        // Compare: the form in flight is the previous one (FormHost latches the form in effect as the
                        // transition starts; this runs after it).
                        onBusyChanged: if (busy && pv.comparing && pv.prev) {
                            latchedForm = pv.prev.forms[pv.surface][latchedDir || "open"]
                        }
                        SampleCard {
                            anchors.fill: parent
                            surface: pv.surface
                            progress: drv.value
                            content: pv.running ? pv.running.accents.content : "late"
                            staggerMs: pv.running ? pv.running.accents.stagger : 0
                            durationMs: pv.runCurves.open ? (pv.runCurves.open.ms || 0) : 0
                        }
                    }
                }
            }

            // --- the miniature bar: a button per class, laid out as on a bar (the island in the middle, modules either
            // side). A toolbar: Tab enters at the class shown, the arrows (Home, End) move along it ---
            Rectangle {
                id: bar
                width: stage.width
                height: pv.barH
                color: Theme.surface
                Accessible.role: Accessible.ToolBar
                Accessible.name: I18n.tr("motion.ui.preview.classes")
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.outline }
                Row {
                    x: 6
                    spacing: 2
                    Repeater { id: leftChips; model: pv.barLeft; delegate: Chip {} }
                }
                Chip { id: islandChip; modelData: "island"; x: (bar.width - width) / 2 }
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    spacing: 2
                    Repeater { id: rightChips; model: pv.barRight; delegate: Chip {} }
                }
            }
        }

        // --- the controls: play again, speed, the scrubber, compare; then what runs ---
        Flow {
            width: parent.width
            spacing: Theme.gap
            Button {
                id: replayBtn
                objectName: "preview-replay"
                label: "↻ " + I18n.tr("motion.ui.preview.replay")
                accessibleName: I18n.tr("motion.ui.preview.replay")
                onClicked: pv.replay()
            }
            MotionText {
                height: Theme.controlH
                verticalAlignment: Text.AlignVCenter
                small: true
                color: Theme.dim
                text: I18n.tr("motion.ui.preview.speed")
            }
            Segmented {
                id: speedSeg
                objectName: "preview-speed"
                choices: [{ value: 1, label: "motion.ui.preview.speed_1" }, { value: 0.5, label: "motion.ui.preview.speed_half" },
                          { value: 0.25, label: "motion.ui.preview.speed_quarter" }]
                current: pv.speed
                cancellable: false
                onPicked: v => pv.speed = v
                onPreviewed: v => pv.speed = v
            }
            Slider {
                id: scrub
                objectName: "preview-scrub"
                width: Math.max(180, Math.min(320, col.width - replayBtn.width - speedSeg.width - compareBtn.width - 140))
                from: 0
                to: 1
                step: 0.01
                value: Math.max(0, Math.min(1, drv.value))
                label: I18n.tr("motion.ui.preview.scrub")
                cancellable: drv.tracking
                // A drag holds the frame under the hand and lets go on release; the arrows hold it until Return or Esc.
                onDragValueChanged: if (dragging) pv.scrubTo(dragValue)
                onDraggingChanged: if (dragging) pv.scrubTo(dragValue); else pv.letGo()
                onPreviewed: v => pv.scrubTo(v)
                onCommitted: v => { if (!dragging) pv.letGo(0) }
                onCancelled: pv.letGo(0)
            }
            // Compare: hold (pointer or Space) to see the motion before the last change.
            RoundBox {
                id: compareBtn
                objectName: "preview-compare"
                implicitWidth: cmpTxt.implicitWidth + 2 * Theme.pad
                width: implicitWidth
                height: Theme.controlH
                radius: Theme.keycap ? height / 2 : Theme.rSm
                color: pv.comparing ? Theme.selected : Theme.containerHigh
                opacity: pv.canCompare ? 1 : 0.5
                border.width: Theme.outlineW > 0 ? Theme.outlineW : 1
                border.color: Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("motion.ui.preview.compare")
                Accessible.description: pv.compareReason
                Accessible.pressed: pv.comparing
                Keys.onPressed: event => {
                    if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) return
                    if (!event.isAutoRepeat) pv.compare(true)
                    event.accepted = true
                }
                Keys.onReleased: event => {
                    if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) return
                    if (!event.isAutoRepeat) pv.compare(false)
                    event.accepted = true
                }
                onActiveFocusChanged: if (!activeFocus) pv.compare(false)
                Text {
                    id: cmpTxt
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    anchors.centerIn: parent
                    color: pv.comparing ? Theme.fgOnSelected : Theme.fg
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: "◐ " + I18n.tr("motion.ui.preview.compare")
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: pv.canCompare
                    onPressed: pv.compare(true)
                    onReleased: pv.compare(false)
                    onCanceled: pv.compare(false)
                }
                FocusRing { anchors.fill: parent; shown: compareBtn.activeFocus; corner: compareBtn.radius }
            }
        }
        MotionText {
            objectName: "preview-state"
            width: parent.width
            small: true
            text: (pv.comparing ? I18n.tr("motion.ui.preview.comparing") + " " : "") + pv.stateText
                + (pv.speed < 1 ? " " + I18n.fmt("motion.ui.preview.slowed", { speed: I18n.tr(pv.speed === 0.5
                    ? "motion.ui.preview.speed_half" : "motion.ui.preview.speed_quarter") }) : "")
        }
        MotionText {
            objectName: "preview-compare-note"
            width: parent.width
            small: true
            color: Theme.dim
            text: pv.compareReason
        }
    }
    readonly property string compareReason: !pv.prev ? I18n.tr("motion.ui.preview.compare_none")
        : pv.compareBlocked ? I18n.tr("motion.ui.preview.compare_blocked")
        : I18n.tr("motion.ui.preview.compare_help")

    // Show a class with its card closed.
    function select(s) {
        if (s === pv.surface) return
        drv.snap(0); drv.to = 0; pv.open = false
        pv.surface = s
        pv.place()
    }
    function moveChip(i) {
        i = Math.max(0, Math.min(pv.barOrder.length - 1, i))
        // Moving along the bar closes the card shown; the next is opened by Space.
        pv.select(pv.barOrder[i])
        var c = pv.chipOf(pv.barOrder[i])
        if (c) c.forceActiveFocus()
    }

    // The state for the settings test (shell.qml `preview`): JSON.
    function state() {
        var sh = host.children[host.children.length - 1]
        return JSON.stringify({
            surface: pv.surface, open: pv.open, value: Number(drv.value.toFixed(4)), running: drv.running,
            tracking: drv.tracking, form: host.form, family: host.family, dir: host.dir, busy: host.busy,
            layer: !!(sh && sh.item), shown: pv.shown, speed: pv.speed, comparing: pv.comparing, canCompare: pv.canCompare,
            ms: pv.runCurves.open ? pv.runCurves.open.ms : 0, card: [Math.round(place.x + stage.x), Math.round(place.y), place.width, place.height]
        })
    }
    // The stage's rect in window coordinates (for a shot's crop).
    function stageRect() {
        var m = stage.mapToItem(null, 0, 0)
        return [Math.round(m.x), Math.round(m.y), Math.round(stage.width), Math.round(stage.height)]
    }
    // The card's rect in window coordinates (for a shot's crop).
    function cardRect() {
        var m = place.mapToItem(null, 0, 0)
        return [Math.round(m.x), Math.round(m.y), Math.round(place.width), Math.round(place.height)]
    }
}
