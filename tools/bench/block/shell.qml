import QtQuick
import Quickshell
import Quickshell.Wayland
import "frontend/core"
import "frontend/components"

// W39-block: what a Block costs. A Quickshell config that `tools/bench/block.sh` copies next to a frontend dir and runs against the real kurashid in a
// sandbox. Once the theme document is in, it makes BLOCK_N quick-tile pairs (a pill Block with a badge Block inside, as
// QuickTile has) BLOCK_ROUNDS times and logs each round's creation time; then it holds BLOCK_HOLD pairs and logs marks for
// the outer script's PSS readings. Every line it logs starts with "BLOCKBENCH".
ShellRoot {
    id: root
    readonly property int n: parseInt(Quickshell.env("BLOCK_N") || "100")
    readonly property int rounds: parseInt(Quickshell.env("BLOCK_ROUNDS") || "15")
    readonly property int hold: parseInt(Quickshell.env("BLOCK_HOLD") || "500")
    property int count: 0
    property int round: -1

    Watch { doc: "theme" }

    function log(s) { console.info("BLOCKBENCH " + s) }

    PanelWindow {
        anchors.top: true
        anchors.left: true
        implicitWidth: 1600
        implicitHeight: 900
        color: "transparent"
        WlrLayershell.namespace: "kurashi-blockbench"
        // The window's tile set, as the Stage has it (K59, W42): a Relief here shares it, not a pair of its own (a window
        // without one made a pair per Relief, which the shell's windows never pay).
        property var tileSheet: tilesLoader.item
        Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
        Flow {
            anchors.fill: parent
            Repeater {
                model: root.count
                Block {
                    width: 160
                    height: 56
                    radius: Theme.rFull
                    fill: index % 2 ? Theme.selected : Theme.containerHigh
                    Block {
                        x: 5
                        y: 8
                        width: 30
                        height: 30
                        radius: Theme.rFull
                        ringScale: 0
                        softScale: 0
                        fill: Theme.container
                    }
                }
            }
        }
    }

    // One step per tick: make the pairs (a Repeater creates them synchronously on the model change) and log the time, or
    // drop them; then the held set and its marks.
    Timer {
        id: step
        interval: 400
        onTriggered: {
            if (root.round < 0) {
                if (Object.keys(Theme.tokens).length === 0) { step.start(); return }
                root.log("theme outline=" + Theme.outlineW + " ring=" + Theme.ringW + " shadow=" + Theme.shadowDy
                         + " soft=" + Theme.softR + " frame=" + Theme.frame + " n=" + root.n)
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
            } else if (root.round === root.rounds) {
                gc()
                root.round++
                step.interval = 3000
                root.log("mark empty")
            } else if (root.round === root.rounds + 1) {
                root.count = root.hold
                gc()
                root.round++
                root.log("mark held " + root.hold)
            } else {
                root.log("done")
                return
            }
            step.start()
        }
    }
    Component.onCompleted: step.start()
}
