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
            face: (Store.island && Store.island.face) || "clock"
            clockText: (Store.clock.hh ?? "--") + ":" + (Store.clock.mm ?? "--") + " · " + (Store.clock.weekday ?? "")
            mediaText: (Store.media.title ?? "") + " — " + (Store.media.artist ?? "")
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
                value: Store.audio.volume ?? 0
                onMoved: v => Store.intent("audio.volume", v, bar.origin)
            }
            Repeater {
                model: (Store.mods && Store.mods.widgets) || []
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
                text: (Store.clock.hh ?? "--") + ":" + (Store.clock.mm ?? "--")
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
