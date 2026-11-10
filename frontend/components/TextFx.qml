import QtQuick
import QtQuick.Effects
import "../core"

// Text effects and fresh text (I473, session 28, docs/ux/text-effects.md; `theme.typography.fx.*`, the daemon's
// `text.*` tokens). Put one INSIDE a Text: `Text { text: …; TextFx { title: true } }`. It changes nothing of the Text
// — its words, size, layout and bindings stay — and adds:
//   the effect   how the text is lit: glow, CRT, candle, rainbow (every letter its own colour), shimmer;
//   fresh text   how it appears when it is made, shown again, or (with `onChange`) when its words change: typed,
//                deciphered, from kana, brushed, rise, ink.
// `title`: a heading (card and page titles, the clock, the island) — what the scope "Headings" covers; a plain label
// takes part only under the scope "Every label". With no effect and no spawn in its scope no copy and no layer is
// made (this object and its bindings always are: I485 asks for that to be measured).
// How: the Text's own glyphs are hidden for the moment (its colour, through a Binding that hands the colour back) and a
// copy drawn in its place inside the Text, so it moves, fades and clips with it. The copy keeps the final layout
// (letters not yet written are there, unseen), so nothing shifts while it is written. Rich text is left alone.
// Ma: a spawn is one short animation; candle and shimmer move only while something is open (ColorFlow.busy) and the
// text is on screen; glow, CRT and rainbow are still.
Item {
    id: fx
    property bool title: false
    property bool onChange: false
    readonly property var target: parent
    readonly property bool inScope: title || Theme.textScope === "all"
    readonly property string spawn: inScope ? Theme.textSpawn : "none"
    readonly property string effect: inScope ? Theme.textEffect : "none"
    readonly property bool plain: !!target && target.text !== undefined
        && (target.textFormat === Text.PlainText || target.textFormat === Text.AutoText)
    width: 0; height: 0

    property real p: 1
    property bool running: false
    property string full: ""
    property color ink: "white"
    readonly property bool hides: (running && spawn !== "none") || (effect === "rainbow" && plain)
    readonly property int ms: Math.round(Math.max(240, Math.min(1100, 90 + full.length * (spawn === "type" ? 34 : 26))) / Theme.textSpawnSpeed)

    function start() {
        if (spawn === "none" || !plain || !target.visible || target.text === "" || target.width <= 0) return
        if (!hides) ink = target.color
        full = target.text
        p = 0
        running = true
        run.restart()
    }
    NumberAnimation {
        id: run
        target: fx; property: "p"; from: 0; to: 1; duration: fx.ms
        easing.type: fx.spawn === "type" || fx.spawn === "decipher" || fx.spawn === "kana" ? Easing.Linear : Easing.OutCubic
        onFinished: fx.running = false
    }
    Binding {
        target: fx.target; property: "color"; value: "transparent"
        when: fx.hides
        restoreMode: Binding.RestoreBindingOrValue
    }
    Connections {
        target: fx.target
        function onVisibleChanged() { if (fx.target.visible) fx.start() }
        function onTextChanged() { if (fx.onChange && !fx.running) fx.start() }
        function onColorChanged() { if (!fx.hides) fx.ink = fx.target.color }
    }
    Component.onCompleted: { if (target && target.color !== undefined) ink = target.color; Qt.callLater(start) }

    // ---- the words while they are written (typed, deciphered, from kana): the final text, the unwritten part unseen ----
    readonly property string cipher: "#%&$@?!*+=<>/[]{}"
    readonly property string kana: "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン"
    function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>") }
    function pick(set, i, tick) { return set.charAt(Math.abs((i * 7919 + tick * 104729) % set.length)) }
    readonly property string written: {
        if (!running) return ""
        var n = full.length, done = Math.floor(p * (n + 3)), s = full
        if (spawn === "type") return esc(s.substring(0, Math.min(n, done))) + hidden(s.substring(Math.min(n, done)))
        var set = spawn === "kana" ? kana : cipher, tick = Math.floor(p * n * 2.5), mid = ""
        var from = Math.min(n, Math.max(0, done - 3)), to = Math.min(n, done + (spawn === "kana" ? 2 : 1))
        for (var i = from; i < to; i++) { var ch = s.charAt(i); mid += /\s/.test(ch) ? ch : pick(set, i, tick) }
        return esc(s.substring(0, from)) + '<font color="' + Qt.alpha(ink, 0.7) + '">' + esc(mid) + "</font>" + hidden(s.substring(to))
    }
    function hidden(s) { return s === "" ? "" : '<font color="#00000000">' + esc(s) + "</font>" }
    // Rainbow: each letter its own colour, round the wheel along the text.
    readonly property string rainbow: {
        if (effect !== "rainbow" || !plain) return ""
        var s = target.text, out = "", k = 0
        for (var i = 0; i < s.length; i++) {
            var ch = s.charAt(i)
            if (/\s/.test(ch)) { out += esc(ch); continue }
            out += '<font color="' + Qt.hsla(((k++) * 0.085) % 1, 0.78, Theme.darkScheme ? 0.7 : 0.42, 1) + '">' + esc(ch) + "</font>"
        }
        return out
    }

    // A copy of the Text with its layout.
    component Copy: Text {
        anchors.fill: parent
        font: fx.target.font
        renderType: fx.target.renderType
        horizontalAlignment: fx.target.horizontalAlignment
        verticalAlignment: fx.target.verticalAlignment
        wrapMode: fx.target.wrapMode
        elide: fx.target.elide
        maximumLineCount: fx.target.maximumLineCount
        lineHeight: fx.target.lineHeight
        lineHeightMode: fx.target.lineHeightMode
        leftPadding: fx.target.leftPadding; rightPadding: fx.target.rightPadding
        topPadding: fx.target.topPadding; bottomPadding: fx.target.bottomPadding
        textFormat: Text.PlainText
        text: fx.target.text
        Accessible.ignored: true
    }

    // ---- fresh text ----
    Loader {
        parent: fx.target
        anchors.fill: parent
        active: fx.running && fx.spawn !== "none"
        sourceComponent: fx.spawn === "rise" ? rise : (fx.spawn === "brush" || fx.spawn === "ink" ? inked : typed)
    }
    Component {
        id: typed
        Copy { textFormat: Text.StyledText; text: fx.written; color: fx.ink }
    }
    Component {
        id: inked
        Copy {
            color: fx.ink
            layer.enabled: true
            layer.effect: ShaderEffect {
                property vector4d uFx: Qt.vector4d(fx.spawn === "ink" ? 1 : 0, fx.p, width, height)
                property vector4d uTint: Qt.vector4d(1, 1, 1, 1)
                fragmentShader: Qt.resolvedUrl("../shaders/text_fx.frag.qsb")
            }
        }
    }
    // Rise: each letter comes up into its place, one after the other. One line only (a wrapped text rises as a whole).
    Component {
        id: rise
        Item {
            readonly property bool single: fx.target.lineCount <= 1 && fx.full.length <= 48
            Copy {
                visible: !parent.single
                color: fx.ink
                opacity: fx.p
                transform: Translate { y: (1 - fx.p) * fx.target.font.pixelSize * 0.5 }
            }
            Row {
                visible: parent.single
                x: fx.target.leftPadding + (fx.target.horizontalAlignment === Text.AlignHCenter ? (fx.target.width - fx.target.contentWidth) / 2
                    : fx.target.horizontalAlignment === Text.AlignRight ? fx.target.width - fx.target.contentWidth : 0)
                y: fx.target.verticalAlignment === Text.AlignVCenter ? (fx.target.height - fx.target.contentHeight) / 2
                    : fx.target.verticalAlignment === Text.AlignBottom ? fx.target.height - fx.target.contentHeight : fx.target.topPadding
                Repeater {
                    model: parent.visible ? fx.full.length : 0
                    Text {
                        required property int index
                        readonly property real t: Math.max(0, Math.min(1, fx.p * (fx.full.length * 0.5 + 3) - index * 0.5) / 3)
                        text: fx.full.charAt(index)
                        font: fx.target.font
                        renderType: fx.target.renderType
                        color: fx.ink
                        opacity: t
                        transform: Translate { y: (1 - t) * (1 - t) * font.pixelSize * 0.7 }
                    }
                }
            }
        }
    }

    // ---- the effect ----
    readonly property bool lit: effect !== "none" && plain && target.visible && target.text !== ""
    readonly property bool moving: lit && Theme.springOn && ColorFlow.busy
    Loader {
        parent: fx.target
        anchors.fill: parent
        z: fx.effect === "rainbow" || fx.effect === "shimmer" ? 1 : -1
        active: fx.lit && !(fx.running && fx.spawn !== "none")
        sourceComponent: fx.effect === "rainbow" ? rainbowed : fx.effect === "shimmer" ? shimmer : glow
    }
    Component {
        id: rainbowed
        Copy { textFormat: Text.StyledText; text: fx.rainbow }
    }
    // Glow, CRT, candle: the letters' own light behind them — a blurred copy; CRT adds the tube's colour fringe, candle
    // a warm light that wavers.
    Component {
        id: glow
        Item {
            id: g
            readonly property bool candle: fx.effect === "candle"
            property real flick: 1
            SequentialAnimation on flick {
                running: g.candle && fx.moving
                loops: Animation.Infinite
                NumberAnimation { to: 0.72; duration: 130 }
                NumberAnimation { to: 1.0; duration: 210 }
                NumberAnimation { to: 0.86; duration: 90 }
                NumberAnimation { to: 0.95; duration: 340 }
                NumberAnimation { to: 0.64; duration: 110 }
                NumberAnimation { to: 1.0; duration: 420 }
            }
            Copy {
                color: g.candle ? Qt.tint(fx.target.color, "#b0ffa030") : fx.target.color
                opacity: (g.candle ? 0.9 : (fx.effect === "crt" ? 0.8 : 0.7)) * g.flick
                layer.enabled: true
                layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: g.candle ? 18 : 12; brightness: 0.15 }
            }
            Copy { visible: fx.effect === "crt"; x: -0.8; color: "#ff3048"; opacity: 0.4; anchors.fill: undefined; width: parent.width; height: parent.height }
            Copy { visible: fx.effect === "crt"; x: 0.8; color: "#30c8ff"; opacity: 0.4; anchors.fill: undefined; width: parent.width; height: parent.height }
        }
    }
    // Shimmer: a light crosses the letters, now and then, while something is open.
    Component {
        id: shimmer
        Copy {
            id: sh
            property real sweep: 0
            visible: pass.running
            color: "white"
            SequentialAnimation {
                id: pass
                running: fx.moving
                loops: Animation.Infinite
                NumberAnimation { target: sh; property: "sweep"; from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
                PauseAnimation { duration: 4200 }
            }
            layer.enabled: true
            layer.effect: ShaderEffect {
                property vector4d uFx: Qt.vector4d(2, sh.sweep, width, height)
                property vector4d uTint: Qt.vector4d(Theme.darkScheme ? 1 : Theme.accent.r, Theme.darkScheme ? 1 : Theme.accent.g, Theme.darkScheme ? 1 : Theme.accent.b, 1)
                fragmentShader: Qt.resolvedUrl("../shaders/text_fx.frag.qsb")
            }
        }
    }
}
