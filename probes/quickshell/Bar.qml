import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    readonly property int barH: Store.tok("bar.height", 36)
    readonly property color fg: Store.color("color.on_surface", "#e9e4d8")
    readonly property color dim: Store.color("color.on_surface_variant", "#b9b2a6")
    readonly property color accent: Store.color("color.accent", "#c9404b")
    readonly property color surface: Qt.alpha(Store.color("color.surface", "#1b1a1e"), Store.tok("color.surface_alpha", 0.82))
    readonly property int pad: Store.tok("space.md", 12)
    readonly property int fs: Store.tok("font.size.body", 13)
    readonly property var fams: [Store.tok("font.family", "Inter"), Store.tok("font.family_jp", "Noto Sans CJK JP")]
    readonly property int stdMs: Store.tok("motion.standard_ms", 220)
    readonly property int emphMs: Store.tok("motion.emphasized_ms", 320)
    readonly property var enterCurve: Store.bezier("motion.easing.enter", [0.05, 0.7, 0.1, 1.0])
    readonly property string origin: "qs:" + (screen ? screen.name : "?") + ":" + Math.floor(Math.random() * 1e6)

    anchors { top: true; left: true; right: true }
    implicitHeight: barH
    color: "transparent"       // exclusionMode defaults to Auto -> exclusive zone = height

    // ext-background-effect-v1 blur (no-op where the compositor lacks the protocol)
    BackgroundEffect.blurRegion: Region { item: bg }

    Rectangle {
        id: bg
        anchors.fill: parent
        color: bar.surface
    }

    // ---- left: workspaces of this output -------------------------------------------------
    Row {
        id: wsRow
        anchors { left: parent.left; leftMargin: bar.pad; verticalCenter: parent.verticalCenter }
        spacing: Store.tok("space.sm", 8)
        Repeater {
            model: {
                var o = (Store.workspaces && Store.workspaces.outputs) || {}
                var n = bar.screen ? bar.screen.name : ""
                return o[n] || o["*"] || []
            }
            delegate: Rectangle {
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                height: modelData.focused ? 10 : 8
                width: modelData.focused ? 24 : 8
                radius: height / 2
                color: modelData.focused ? bar.accent : (modelData.occupied ? bar.fg : "transparent")
                border.width: (!modelData.focused && !modelData.occupied) ? 1 : 0
                border.color: bar.dim
                Behavior on width { NumberAnimation { duration: bar.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: bar.enterCurve } }
            }
        }
    }

    // ---- center: Island ---------------------------------------------------------------------
    Rectangle {
        id: island
        anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
        height: bar.barH - 10
        radius: Store.tok("radius.full", 999)
        color: Store.color("color.surface_container_high", "#2f2c33")
        readonly property bool media: Store.island && Store.island.face === "media"
        readonly property real target: (media ? mediaText.implicitWidth : clockText.implicitWidth) + 2 * bar.pad
        property bool armed: false
        width: target
        Component.onCompleted: armed = true
        Behavior on width {
            enabled: island.armed
            NumberAnimation { duration: bar.emphMs; easing.type: Easing.BezierSpline; easing.bezierCurve: bar.enterCurve }
        }
        clip: true

        Text {
            id: clockText
            anchors.centerIn: parent
            color: bar.fg
            font.pixelSize: bar.fs
            font.family: Store.fam(text, bar.fams)
            text: (Store.clock.hh ?? "--") + ":" + (Store.clock.mm ?? "--") + " · " + (Store.clock.weekday ?? "")
            opacity: island.media ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { enabled: island.armed; NumberAnimation { duration: bar.emphMs; easing.type: Easing.BezierSpline; easing.bezierCurve: bar.enterCurve } }
        }
        Text {
            id: mediaText
            anchors.centerIn: parent
            color: bar.fg
            font.pixelSize: bar.fs
            font.family: Store.fam(text, bar.fams)
            text: (Store.media.title ?? "") + " — " + (Store.media.artist ?? "")
            opacity: island.media ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { enabled: island.armed; NumberAnimation { duration: bar.emphMs; easing.type: Easing.BezierSpline; easing.bezierCurve: bar.enterCurve } }
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => Store.act(m.button === Qt.RightButton ? "island.pin" : "probe.popup.toggle")
            onWheel: w => { if (w.angleDelta.y !== 0) Store.act(w.angleDelta.y > 0 ? "island.prev" : "island.next") }
        }
    }

    // ---- right: volume, mod widget, clock ---------------------------------------------------
    Row {
        anchors { right: parent.right; rightMargin: bar.pad; verticalCenter: parent.verticalCenter }
        spacing: bar.pad
        Slider {
            anchors.verticalCenter: parent.verticalCenter
            width: 110
            value: Store.audio.volume ?? 0
            track: Store.color("color.outline", "#5a5560")
            fill: bar.accent
            onMoved: v => Store.intent("audio.volume", v, bar.origin)
        }
        Repeater {
            model: (Store.mods && Store.mods.widgets) || []
            delegate: Node {
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                node: modelData.ui
                wstate: modelData.state || ({})
                fg: bar.fg
                size: bar.fs
                families: bar.fams
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: bar.fg
            font.pixelSize: bar.fs
            font.family: Store.fam(text, bar.fams)
            text: (Store.clock.hh ?? "--") + ":" + (Store.clock.mm ?? "--")
        }
    }

    // ---- popup (xdg_popup child of this layer surface, anchored under the Island) ---------------
    PopupWindow {
        id: popup
        readonly property bool want: Store.ui && Store.ui.popup === true
        property real p: 0                  // reveal progress 0..1
        property bool gate: false           // waiting for first presented frame
        anchor.window: bar
        anchor.rect.x: (bar.width - 360) / 2
        anchor.rect.y: bar.barH
        anchor.rect.width: 360
        anchor.rect.height: 1
        anchor.edges: Edges.Top | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        implicitWidth: 360
        implicitHeight: 220
        color: "transparent"
        visible: false
        BackgroundEffect.blurRegion: Region { item: card }

        onWantChanged: {
            if (want) {
                anim.stop()
                if (!visible) { p = 0; gate = true; visible = true }   // reveal waits for first frame
                else { anim.from = p; anim.to = 1; anim.start() }
            } else if (visible) {
                gate = false
                anim.stop(); anim.from = p; anim.to = 0; anim.start()
            }
        }
        NumberAnimation {
            id: anim
            target: popup; property: "p"
            duration: bar.stdMs
            easing.type: Easing.BezierSpline; easing.bezierCurve: bar.enterCurve
            onFinished: if (popup.p <= 0 && !popup.want) popup.visible = false
        }
        Connections {
            target: card.Window.window
            function onFrameSwapped() {
                if (popup.gate) { popup.gate = false; anim.from = popup.p; anim.to = 1; anim.start() }
            }
        }

        Rectangle {
            id: card
            anchors.fill: parent
            opacity: popup.p
            scale: 0.96 + 0.04 * popup.p
            radius: Store.tok("radius.lg", 18)
            color: Store.color("color.surface_container", "#252329")
            border.width: 1
            border.color: Store.color("color.outline", "#5a5560")
            focus: true
            Keys.onEscapePressed: Store.act("probe.popup.toggle")

            Column {
                anchors { fill: parent; margins: bar.pad + 4 }
                spacing: bar.pad
                Text {
                    color: bar.fg
                    font.pixelSize: Store.tok("font.size.title", 16)
                    font.family: Store.fam(text, bar.fams)
                    text: "暮らし · quickshell probe"
                }
                Rectangle {
                    width: parent.width; height: 32
                    radius: Store.tok("radius.sm", 6)
                    color: Store.color("color.surface", "#1b1a1e")
                    border.width: 1; border.color: field.activeFocus ? bar.accent : Store.color("color.outline", "#5a5560")
                    TextInput {
                        id: field
                        anchors { fill: parent; margins: 6 }
                        color: bar.fg
                        font.pixelSize: bar.fs
                        font.family: Store.fam(text, bar.fams)
                        verticalAlignment: TextInput.AlignVCenter
                        selectByMouse: true
                        Keys.onEscapePressed: Store.act("probe.popup.toggle")
                    }
                }
                ShaderEffect {
                    id: fx
                    width: 200; height: 80
                    property real time: 0
                    property color c1: Store.color("color.accent", "#c9404b")
                    property color c2: Store.color("color.secondary", "#5b7fa6")
                    fragmentShader: Qt.resolvedUrl("shader.frag.qsb")
                    visible: popup.visible
                    FrameAnimation {
                        running: popup.visible
                        onTriggered: fx.time += frameTime
                    }
                }
            }
        }
    }
}
