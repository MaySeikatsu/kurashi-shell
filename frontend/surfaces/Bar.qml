import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"

// One bar per output. Everything shown comes from Store; every click becomes an act/intent.
PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    readonly property string origin: "qs:" + (screen ? screen.name : "?") + ":" + Math.floor(Math.random() * 1e6)
    // Veil: daemon away (or not yet current) -> keep last state, dim it, show the glyph.
    readonly property bool stale: !Store.live

    // What this bar renders; unwatched when the bar goes away (output unplugged) so the daemon can
    // stop services nobody shows (Ma).
    Watch { doc: "svc.clock" }
    Watch { doc: "svc.workspaces" }
    Watch { doc: "svc.media" }
    Watch { doc: "runtime.island.main" }
    Watch { doc: "svc.audio" }
    Watch { doc: "mods.probe" }
    readonly property var clock: Store.docs["svc.clock"] || ({})
    readonly property var workspaces: Store.docs["svc.workspaces"] || ({})
    readonly property var media: Store.docs["svc.media"] || ({})
    readonly property var island: Store.docs["runtime.island.main"] || ({})
    readonly property var audio: Store.docs["svc.audio"] || ({})
    readonly property var mods: Store.docs["mods.probe"] || ({})

    anchors { top: true; left: true; right: true }
    implicitHeight: Theme.barH
    color: "transparent"       // exclusionMode Auto -> exclusive zone = height

    // ext-background-effect-v1 blur (no-op where the compositor lacks the protocol)
    BackgroundEffect.blurRegion: Region { item: bg }

    Rectangle {
        id: bg
        anchors.fill: parent
        color: Theme.surfaceAlpha
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: bar.stale ? Theme.staleOpacity : 1
        Behavior on opacity {
            enabled: bar.visible
            NumberAnimation { duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
        }

        // ---- left: workspaces of this output ----------------------------------------------
        Row {
            anchors { left: parent.left; leftMargin: Theme.pad; verticalCenter: parent.verticalCenter }
            spacing: Theme.gap
            Repeater {
                model: {
                    var o = bar.workspaces.outputs || {}
                    var n = bar.screen ? bar.screen.name : ""
                    return o[n] || o["*"] || []
                }
                delegate: Rectangle {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    height: modelData.focused ? 10 : 8
                    width: modelData.focused ? 24 : 8
                    radius: height / 2
                    color: modelData.focused ? Theme.accent : (modelData.occupied ? Theme.fg : "transparent")
                    border.width: (!modelData.focused && !modelData.occupied) ? 1 : 0
                    border.color: Theme.dim
                    Behavior on width {
                        enabled: bar.visible
                        NumberAnimation { duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
                    }
                }
            }
        }

        // ---- center: Island ----------------------------------------------------------------
        Island {
            anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
            face: bar.island.face || "clock"
            clockText: (bar.clock.hh ?? "--") + ":" + (bar.clock.mm ?? "--") + " · " + (bar.clock.weekday ?? "")
            reason: bar.island.reason || "default"
            mediaText: (bar.media.title ?? "") + " — " + (bar.media.artist ?? "")
            onPrimary: Store.act("probe.popup.toggle")
            onSecondary: Store.act("island.pin")
            onScrolled: dir => Store.act(dir > 0 ? "island.prev" : "island.next")
        }

        // ---- right: volume, mod widgets, clock ----------------------------------------------
        Row {
            anchors { right: parent.right; rightMargin: Theme.pad; verticalCenter: parent.verticalCenter }
            spacing: Theme.pad
            Slider {
                anchors.verticalCenter: parent.verticalCenter
                width: 110
                value: bar.audio.volume ?? 0
                onMoved: v => Store.intent("audio.volume", v, bar.origin)
            }
            Repeater {
                model: bar.mods.widgets || []
                delegate: ModNode {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    node: modelData.ui
                    wstate: modelData.state || ({})
                    fg: Theme.fg
                    size: Theme.fs
                    families: Theme.families
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: (bar.clock.hh ?? "--") + ":" + (bar.clock.mm ?? "--")
            }
        }
    }

    // Disconnected glyph: instantiated only while stale (nothing at idle).
    Loader {
        anchors { left: parent.left; leftMargin: 120; verticalCenter: parent.verticalCenter }
        active: bar.stale
        sourceComponent: Text {
            color: Theme.accent
            font.pixelSize: Theme.fs - 2
            font.family: Theme.fam(text, Theme.families)
            text: "⊘ " + I18n.tr("frontend.bar.disconnected")
        }
    }
}
