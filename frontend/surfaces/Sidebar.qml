import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"
import "../components/sidebar"

// An edge sidebar (card W29, docs/ux/sidebar.md): `side` left or right, open while runtime.ui.sidebar names it (the daemon
// decides, one at a time with the Stage's panels and the launcher). One layer surface on the asking output
// (runtime.ui.sidebar_output, else the focused one, latched while open); closed = no window at all, 0 frames, no
// subscription (Ma). The window is anchored top + bottom + its side with exclusive zone 0, so the compositor stops it at
// a bar's inner edge on any side and lets it run edge to edge where no bar reserves space (copied from ii
// `modules/ii/sidebarRight/SidebarRight.qml`; shellseikatsu's own arithmetic for the bar's size broke under side bars —
// its docs/BUGS.md). Input is masked to the column, so a floating column's gap passes clicks through.
// `sidebar.style`: panel = flush, outer corners square, inner corners `radius.lg`; floating = inset by `space.sm`, every
// corner rounded, the look's Block (ring, hard or soft shadow). Tokens only (rule 4). It slides in from its edge on the
// theme's spring and out on the standard curve; `Theme.springOn` false: at once. Esc backs out of a page, then closes.
Scope {
    id: sb
    required property string side            // "left" | "right"
    // shell.qml's focused output, read when the sidebar opens without a named output.
    property var focusedScreen: null

    readonly property var ui: Store.docs["runtime.ui"] || ({})
    readonly property bool wanted: ui.sidebar === side
    readonly property string wantOutput: wanted && typeof ui.sidebar_output === "string" ? ui.sidebar_output : ""

    // The output it is on: picked when it opens, or when the daemon names another output while it is open.
    property var screen: null
    // The window exists: open, or sliding out.
    property bool held: false
    // Slide progress, 0 = past its edge, 1 = in place.
    property real p: 0
    readonly property bool instant: !Theme.springOn

    function screenNamed(n) {
        var s = Quickshell.screens
        for (var i = 0; i < s.length; i++) if (s[i].name === n) return s[i]
        return null
    }
    function pick() {
        var s = wantOutput !== "" ? screenNamed(wantOutput) : null
        return s !== null ? s : (focusedScreen || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null))
    }
    // Test only (frontend/test-texture.sh, the carried sheet): the column holds at this slide progress instead of coming in.
    readonly property real holdP: Quickshell.env("KURASHI_SIDEBAR_HOLD") ? Number(Quickshell.env("KURASHI_SIDEBAR_HOLD")) : -1
    onWantedChanged: {
        if (wanted && holdP >= 0) {
            if (!held) { screen = pick(); held = true }
            gate = false
            p = holdP
            return
        }
        if (wanted) {
            closeAnim.stop()
            if (!held) { screen = pick(); p = 0; gate = !instant; held = true }
            if (instant) p = 1
            else if (!gate) springTo(1)
        } else if (held) {
            gate = false
            if (instant) { p = 0; held = false }
            else { spring.stop(); closeAnim.from = p; closeAnim.start() }
        }
    }
    onWantOutputChanged: if (wanted && held) screen = pick()

    // The slide starts on the first presented frame of the new window (as the Stage's reveal), so it is never skipped.
    property bool gate: false
    function springTo(v) { closeAnim.stop(); spring.from = p; spring.to = v; spring.start() }
    SpringAnimation {
        id: spring
        target: sb; property: "p"
        spring: Theme.spring
        damping: Math.max(0.3, Theme.damping)
        epsilon: 0.002
    }
    NumberAnimation {
        id: closeAnim
        target: sb; property: "p"
        to: 0
        duration: Theme.stdMs
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve
        onFinished: if (!sb.wanted) sb.held = false
    }

    // This output's config (an output's own entry wins); the sidebar keys are global.
    BarConfig { id: cfg; screen: sb.screen }
    readonly property bool floating: cfg.valueOf("sidebar.style", "panel") === "floating"
    readonly property int wantW: {
        var w = Number(cfg.valueOf("sidebar.width", 420))
        return isNaN(w) ? 420 : Math.max(320, Math.min(640, Math.round(w)))
    }
    // Never wider than the output less a gap.
    readonly property int colW: Math.min(wantW, screen ? screen.width - Theme.gap : wantW)
    readonly property var sections: {
        var v = cfg.valueOf(side === "left" ? "sidebar.left" : "sidebar.right", side === "left" ? ["mod:ai:ai"]
            : ["header", "toggles", "sliders", "notifications", "calendar"])
        return Array.isArray(v) ? v.filter(function (s) { return typeof s === "string" && s !== "" }) : []
    }
    readonly property bool geometryLog: Quickshell.env("KURASHI_SIDEBAR_GEOMETRY") === "1"

    LazyLoader {
        active: sb.held
        PanelWindow {
            id: win
            screen: sb.screen
            anchors {
                top: true
                bottom: true
                left: sb.side === "left"
                right: sb.side === "right"
            }
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            implicitWidth: sb.colW
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "kurashi-sidebar"
            WlrLayershell.keyboardFocus: sb.wanted ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            mask: Region { item: frame }
            BackgroundEffect.blurRegion: Region { item: frame }

            readonly property string outName: sb.screen ? sb.screen.name : ""
            // K59: this window's tile set, shared by its reliefs, and the pointer light's sensor. K61: the column's carry
            // while it slides (`texture.sheet = carried`): its material comes in with it and lands on the continuous sheet.
            property var tileSheet: tilesLoader.item
            readonly property point sheetCarry: Qt.point(frame.x - frame.restX, 0)
            Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
            LightSense {}
            function logGeom() {
                if (!sb.geometryLog) return
                console.log("sidebar-geom " + outName + " " + sb.side + " " + (sb.floating ? "floating" : "panel")
                    + " win " + win.width + " " + win.height + " frame " + Math.round(frame.restX) + "," + Math.round(frame.y)
                    + "," + Math.round(frame.width) + "," + Math.round(frame.height) + " bar " + (cfg.enabled ? cfg.edge : "none")
                    + " " + Theme.barH + " gap " + Theme.gap + " sections " + sb.sections.join(","))
            }
            onWidthChanged: logGeom()
            onHeightChanged: logGeom()
            Component.onCompleted: { if (sb.geometryLog) console.log("sidebar-window up " + sb.side); logGeom() }
            Component.onDestruction: if (sb.geometryLog) console.log("sidebar-window down " + sb.side)
            Connections {
                target: frame.Window.window
                function onFrameSwapped() {
                    if (!sb.gate) return
                    sb.gate = false
                    if (sb.wanted) sb.springTo(1)
                }
            }

            // The column: its place at rest (`restX`), and the slide past its own edge.
            Item {
                id: frame
                readonly property real inset: sb.floating ? Theme.gap : 0
                readonly property real restX: inset
                // A spring past its target is held at the edge: a flush panel cannot overshoot into the screen.
                readonly property real shown: Math.max(0, Math.min(1, sb.p))
                x: restX + (sb.side === "right" ? 1 : -1) * (1 - shown) * (win.width)
                y: inset
                width: win.width - 2 * inset
                height: win.height - 2 * inset
                onHeightChanged: win.logGeom()

                // Panel: flush to the side, square outer corners, the two inner ones rounded.
                Rectangle {
                    id: panelRect
                    visible: !sb.floating
                    anchors.fill: parent
                    color: Theme.panel
                    topLeftRadius: sb.side === "right" ? Theme.rLg : 0
                    bottomLeftRadius: sb.side === "right" ? Theme.rLg : 0
                    topRightRadius: sb.side === "left" ? Theme.rLg : 0
                    bottomRightRadius: sb.side === "left" ? Theme.rLg : 0
                    // K62: with a pen in effect the pen draws the panel's outline instead of the straight border.
                    border.width: panelPen.active ? 0 : (Theme.outlineW > 0 ? Theme.outlineW : 1)
                    border.color: Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline
                    Loader {
                        id: panelPen
                        anchors.fill: parent
                        active: Theme.penOutline && panelRect.visible
                        sourceComponent: PenOutline {
                            radii: [panelRect.topLeftRadius, panelRect.topRightRadius, panelRect.bottomRightRadius,
                                    panelRect.bottomLeftRadius]
                            color: panelRect.border.color
                            lineWidth: Theme.outlineW > 0 ? Theme.outlineW : 1
                            seed: sb.side === "left" ? 0x51DE1 : 0x51DE2
                        }
                    }
                }
                // K59: the panel is a material area; the relief lies under the content (over it with texture.text). Its
                // corners are the panel's (the outer ones square). Floating, the Block carries its own.
                Loader {
                    z: Theme.texText ? 2 : 0
                    anchors.fill: parent
                    anchors.margins: Theme.outlineW
                    active: !sb.floating && Theme.texShell
                    sourceComponent: Relief {
                        readonly property real r: Math.max(0, Theme.rLg - Theme.outlineW)
                        anchors.fill: parent
                        topLeftRadius: sb.side === "right" ? r : 0
                        bottomLeftRadius: sb.side === "right" ? r : 0
                        topRightRadius: sb.side === "left" ? r : 0
                        bottomRightRadius: sb.side === "left" ? r : 0
                    }
                }
                // Floating: the look's block (keycap ring and hard shadow, soft shadow, line outline).
                Block {
                    visible: sb.floating
                    anchors.fill: parent
                    fill: Theme.panel
                    radius: Theme.rLg
                    flatBorder: Theme.outline
                    animate: false
                    // K62: the pen's salt for its outline: the side, not its place (it slides in).
                    penSeed: sb.side === "left" ? 0x51DE1 : 0x51DE2
                }

                // The content, the column's one keyboard focus holder: Esc backs out of a page first, then closes.
                FocusScope {
                    id: content
                    x: Theme.pad
                    y: Theme.pad
                    width: frame.width - 2 * Theme.pad
                    height: frame.height - (sb.floating ? Theme.shadowDy : 0) - 2 * Theme.pad
                    focus: true
                    Keys.onPressed: event => {
                        if (event.key !== Qt.Key_Escape) return
                        if (!(col.item && col.item.back && col.item.back())) Store.act("sidebar.close")
                        event.accepted = true
                    }
                    Component.onCompleted: Qt.callLater(function () { content.forceActiveFocus() })
                    Accessible.role: Accessible.Pane
                    Accessible.name: I18n.tr(sb.side === "left" ? "sidebar.a11y.left" : "sidebar.a11y.right")

                    Loader {
                        id: col
                        anchors.fill: parent
                        focus: true
                        sourceComponent: sb.side === "left" ? leftC : rightC
                    }
                }
            }
        }
    }
    Component {
        id: rightC
        RightColumn { sections: sb.sections; outName: sb.screen ? sb.screen.name : "" }
    }
    Component {
        id: leftC
        LeftColumn { tabs: sb.sections }
    }
}
