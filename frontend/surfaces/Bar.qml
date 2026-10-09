import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"

// One bar per output, on the edge that output's config names (bar.edge). bar.enabled false: no
// surface, no exclusive zone and no subscriptions held for it (Ma). Everything shown comes from
// Store; every click becomes an act/intent.
PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    // This output's bar settings (config document, per-output entry wins).
    BarConfig { id: cfg; screen: bar.screen }
    readonly property bool vertical: cfg.vertical

    readonly property string origin: "qs:" + (screen ? screen.name : "?") + ":" + Math.floor(Math.random() * 1e6)
    // Veil: daemon away (or not yet current) -> keep last state, dim it, show the glyph.
    readonly property bool stale: !Store.live

    // What this bar renders; unwatched while the bar is hidden or gone so the daemon can stop
    // services nobody shows (Ma).
    Watch { doc: "svc.clock"; active: bar.visible }
    Watch { doc: "svc.workspaces"; active: bar.visible }
    Watch { doc: "runtime.island.main"; active: bar.visible }
    Watch { doc: "svc.audio"; active: bar.visible }
    Watch { doc: "mods.probe"; active: bar.visible }
    // Input bindings (ARCHITECTURE §6): what each island slot runs. Only while this bar is shown.
    Watch { doc: "bindings"; active: bar.visible }
    readonly property var clock: Store.docs["svc.clock"] || ({})
    readonly property var workspaces: Store.docs["svc.workspaces"] || ({})
    readonly property var island: Store.docs["runtime.island.main"] || ({})
    readonly property var audio: Store.docs["svc.audio"] || ({})
    readonly property var mods: Store.docs["mods.probe"] || ({})
    readonly property var bindings: Store.docs["bindings"] || ({})
    readonly property real daemonVolume: audio.volume ?? 0
    // This output's workspace pills, or the "*" list when the daemon sends one for all outputs.
    readonly property var pills: {
        var o = workspaces.outputs || {}
        var n = screen ? screen.name : ""
        return o[n] || o["*"] || []
    }

    // Volume intents. A wheel notch is one 5 % step from the last value sent, so fast scrolling
    // does not lose steps while the daemon's echo is still on its way; the echo resets it.
    property real volumeTarget: -1
    onDaemonVolumeChanged: volumeTarget = -1
    function setVolume(v) {
        volumeTarget = -1
        Store.intent("audio.volume", v, origin)
    }
    function volumeStep(dy) {
        if (dy === 0) return
        var base = volumeTarget >= 0 ? volumeTarget : daemonVolume
        volumeTarget = Math.max(0, Math.min(1, base + (dy > 0 ? 0.05 : -0.05)))
        Store.intent("audio.volume", volumeTarget, origin)
    }

    // Anchored to its edge: a left or right bar spans the height, a top or bottom bar the width.
    anchors {
        top: cfg.edge === "top" || vertical
        bottom: cfg.edge === "bottom" || vertical
        left: cfg.edge === "left" || !vertical
        right: cfg.edge === "right" || !vertical
    }
    implicitHeight: vertical ? 0 : Theme.barH
    implicitWidth: vertical ? Theme.barH : 0
    visible: cfg.enabled
    color: "transparent"       // exclusionMode Auto -> exclusive zone = the bar's thickness

    // ext-background-effect-v1 blur (no-op where the compositor lacks the protocol)
    BackgroundEffect.blurRegion: Region { item: bg }

    Rectangle {
        id: bg
        anchors.fill: parent
        color: Theme.surfaceAlpha
    }

    // One layout is active at a time: a row on top and bottom bars, a column on left and right.
    // Nothing is instantiated while the bar is hidden, so its faces hold no subscriptions (Ma).
    Loader {
        anchors.fill: parent
        active: bar.visible && !bar.vertical
        sourceComponent: horizontalLayout
    }
    Loader {
        anchors.fill: parent
        active: bar.visible && bar.vertical
        sourceComponent: verticalLayout
    }

    // ---- top and bottom bars: workspaces left, Island centre, the rest right --------------------
    Component {
        id: horizontalLayout
        Item {
            anchors.fill: parent
            opacity: bar.stale ? Theme.staleOpacity : 1
            Behavior on opacity {
                enabled: bar.visible
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
            }

            Row {
                id: workspaceRow
                anchors { left: parent.left; leftMargin: Theme.pad; verticalCenter: parent.verticalCenter }
                spacing: Theme.gap
                Repeater {
                    model: bar.pills
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
            // Disconnected glyph: instantiated only while stale (nothing at idle), after the workspaces.
            Loader {
                anchors { left: workspaceRow.right; leftMargin: Theme.gap; verticalCenter: parent.verticalCenter }
                active: bar.stale
                sourceComponent: Text {
                    color: Theme.accent
                    font.pixelSize: Theme.fs - 2
                    font.family: Theme.fam(text, Theme.families)
                    text: "⊘ " + I18n.tr("frontend.bar.disconnected")
                }
            }

            Island {
                anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
                face: bar.island.face || "clock"
                reason: bar.island.reason || "default"
                slots: bar.bindings["island.main"] || ({})
                // The user's binding decides what a slot does; an absent slot never reaches here.
                onActivated: slot => Store.act("input.dispatch", {component: "island.main", slot: slot})
            }

            Row {
                anchors { right: parent.right; rightMargin: Theme.pad; verticalCenter: parent.verticalCenter }
                spacing: Theme.pad
                Slider {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 110
                    value: bar.daemonVolume
                    onMoved: v => bar.setVolume(v)
                    WheelHandler { onWheel: event => bar.volumeStep(event.angleDelta.y) }
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
    }

    // ---- left and right bars: the same items in one column. Wrapper items keep the column's
    // positioner away from anchors; the Island and the slider are turned to run along the bar.
    Component {
        id: verticalLayout
        Item {
            anchors.fill: parent
            opacity: bar.stale ? Theme.staleOpacity : 1
            Behavior on opacity {
                enabled: bar.visible
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
            }

            Column {
                id: workspaceCol
                anchors { top: parent.top; topMargin: Theme.pad; horizontalCenter: parent.horizontalCenter }
                spacing: Theme.gap
                Repeater {
                    model: bar.pills
                    delegate: Item {
                        required property var modelData
                        width: Theme.barH
                        height: modelData.focused ? 24 : 8
                        Rectangle {
                            anchors.centerIn: parent
                            width: modelData.focused ? 10 : 8
                            height: parent.height
                            radius: width / 2
                            color: modelData.focused ? Theme.accent : (modelData.occupied ? Theme.fg : "transparent")
                            border.width: (!modelData.focused && !modelData.occupied) ? 1 : 0
                            border.color: Theme.dim
                        }
                    }
                }
            }
            // Disconnected glyph under the workspaces; the label does not fit a bar this thin.
            Loader {
                anchors { top: workspaceCol.bottom; topMargin: Theme.gap; horizontalCenter: parent.horizontalCenter }
                active: bar.stale
                sourceComponent: Text {
                    color: Theme.accent
                    font.pixelSize: Theme.fs - 2
                    font.family: Theme.fam(text, Theme.families)
                    text: "⊘"
                }
            }

            Island {
                anchors.centerIn: parent
                rotation: cfg.edge === "left" ? -90 : 90
                face: bar.island.face || "clock"
                reason: bar.island.reason || "default"
                slots: bar.bindings["island.main"] || ({})
                onActivated: slot => Store.act("input.dispatch", {component: "island.main", slot: slot})
            }

            Column {
                anchors { bottom: parent.bottom; bottomMargin: Theme.pad; horizontalCenter: parent.horizontalCenter }
                spacing: Theme.gap
                Item {
                    width: Theme.barH
                    height: 110
                    Slider {
                        anchors.centerIn: parent
                        width: 110
                        rotation: -90
                        value: bar.daemonVolume
                        onMoved: v => bar.setVolume(v)
                        WheelHandler { onWheel: event => bar.volumeStep(event.angleDelta.y) }
                    }
                }
                Repeater {
                    model: bar.mods.widgets || []
                    delegate: Item {
                        required property var modelData
                        width: Theme.barH
                        height: Theme.barH
                        ModNode {
                            anchors.centerIn: parent
                            node: modelData.ui
                            wstate: modelData.state || ({})
                            fg: Theme.fg
                            size: Theme.fs
                            families: Theme.families
                        }
                    }
                }
                Text {
                    width: Theme.barH
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: (bar.clock.hh ?? "--") + "\n" + (bar.clock.mm ?? "--")
                }
            }
        }
    }
}
