import QtQuick
import Quickshell
import Quickshell.Wayland
import "frontend/core"
import "frontend/components"
import "frontend/components/quick"

// W42-tiles: what a quick tile costs (QuickTile with its Blocks, Icons, Texts and areas). A Quickshell config that
// `tools/bench/tile.sh` copies next to a frontend dir and runs against the real kurashid in a sandbox, as block/shell.qml
// does for Blocks: once the theme document is in, it makes TILE_N tiles TILE_ROUNDS times and logs each round's creation
// time (a Repeater creates them synchronously on the model change). Every line it logs starts with "TILEBENCH".
ShellRoot {
    id: root
    readonly property int n: parseInt(Quickshell.env("TILE_N") || "120")
    readonly property int rounds: parseInt(Quickshell.env("TILE_ROUNDS") || "15")
    property int count: 0
    property int round: -1

    Watch { doc: "theme" }

    function log(s) { console.info("TILEBENCH " + s) }

    PanelWindow {
        anchors.top: true
        anchors.left: true
        implicitWidth: 1600
        implicitHeight: 900
        color: "transparent"
        WlrLayershell.namespace: "kurashi-tilebench"
        // The window's tile set, as the Stage has it (K59, W42): see block/shell.qml.
        property var tileSheet: tilesLoader.item
        Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
        Flow {
            anchors.fill: parent
            Repeater {
                model: root.count
                QuickTile {
                    glyph: "≋"
                    icon: index % 2 ? "wifi" : "bluetooth"
                    label: "Tile " + index
                    subtitle: index % 3 ? "connected" : ""
                    on: index % 2 === 1
                    hasPage: index % 3 !== 2
                }
            }
        }
    }

    // One step per tick: make the tiles and log the time, or drop them.
    Timer {
        id: step
        interval: 400
        onTriggered: {
            if (root.round < 0) {
                if (Object.keys(Theme.tokens).length === 0) { step.start(); return }
                root.log("theme n=" + root.n + " rounds=" + root.rounds)
                root.round = 0
            } else if (root.round < root.rounds) {
                if (root.count === 0) {
                    var t = Date.now()
                    root.count = root.n
                    root.log("round " + root.round + " ms " + (Date.now() - t))
                } else {
                    root.count = 0
                    root.round++
                    gc()
                }
            } else {
                root.log("done")
                return
            }
            step.start()
        }
    }
    Component.onCompleted: step.start()
}
