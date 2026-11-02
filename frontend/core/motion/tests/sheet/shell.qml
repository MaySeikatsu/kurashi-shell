import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "frontend/core"
import "frontend/core/motion"
import "frontend/components"
import "frontend/components/motion"

// The sheet forms' harness (W59.4, K83): a realistic card (a Block with the look's fill, material and text) in a FormHost,
// hung from the bar's edge like each surface class, so fold, roll, book and crumple are seen and scrubbed before the
// surfaces carry them (W59.3). `frontend/core/motion/tests/sheet/run.sh` puts this file beside a `frontend` link and runs
// it on the nested niri against the real kurashid; the form comes from the theme tokens (theme.motion.form.<surface>.*),
// so FormHost latches and loads it as on a real surface. Driven over IPC (`qs ipc call sheet …`), every frame is
// deterministic:
//   scene <name>     panel | launcher | sidebar | toast | bottom (a panel on a bottom bar) | right (a sidebar on the right)
//   at <p>           hold progress at p (a transition starts from the rest it left: 1 → close, 0 → open)
//   play <to>        run the Driver to 0 or 1 on the theme's curves (the real timing; reversal: play again mid-way)
//   info             the sheet's state (form, family, busy, handover values)
// Every line it logs starts with "SHEETHARNESS".
ShellRoot {
    id: root
    property string sceneName: Quickshell.env("SHEET_SCENE") || "panel"
    property bool driven: false
    property real held: 1
    Watch { doc: "theme" }
    function log(s) { console.info("SHEETHARNESS " + s) }

    // The scenes: the card's rect in the window (below the bar), its edge, and the origin (the pressed module).
    readonly property var scenes: ({
        panel: { x: 560, y: 0, w: 620, h: 430, edge: "top", surface: "panel", ox: 820, ow: 120 },
        launcher: { x: 600, y: 0, w: 720, h: 520, edge: "top", surface: "launcher", ox: 900, ow: 120 },
        sidebar: { x: 0, y: 0, w: 380, h: 1000, edge: "left", surface: "sidebar", ox: -1, ow: 0 },
        right: { x: 1540, y: 0, w: 380, h: 1000, edge: "right", surface: "sidebar", ox: -1, ow: 0 },
        toast: { x: 1500, y: 12, w: 400, h: 104, edge: "right", surface: "toast", ox: -1, ow: 0 },
        bottom: { x: 560, y: 0, w: 620, h: 430, edge: "bottom", surface: "panel", ox: 820, ow: 120 }
    })
    readonly property var sc: scenes[sceneName] || scenes.panel

    IpcHandler {
        target: "sheet"
        function scene(name: string): string {
            root.driven = false
            root.held = 1
            root.sceneName = name
            return name
        }
        function at(p: real): string {
            root.driven = false
            // (a jump from one rest to the other passes through the middle: FormHost notes the rest it leaves only
            // when a transition starts)
            if ((p === 0 || p === 1) && (root.held === 0 || root.held === 1) && p !== root.held) root.held = 0.5
            root.held = p
            return root.state()
        }
        function play(to: real): string {
            if (!root.driven) { driver.snap(host.progress); root.driven = true }
            driver.to = to
            return "playing to " + to
        }
        function info(): string { return root.state() }
    }
    function state() {
        var s = host.children[host.children.length - 1].item
        return "p=" + host.progress.toFixed(3) + " form=" + host.form + " family=" + host.family + " dir=" + host.dir
            + " busy=" + host.busy + (s ? " shadowK=" + s.shadowK.toFixed(3) + " filletK=" + s.filletK.toFixed(3)
            + " nd=" + (s.nd || "-") + " na=" + (s.na || "-") : "") + " light=" + Theme.lightDirToken
    }

    Driver {
        id: driver
        curves: Theme.motionCurves
    }

    PanelWindow {
        id: win
        anchors { top: true; left: true; right: true; bottom: true }
        exclusionMode: ExclusionMode.Normal
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "kurashi-sheet-harness"
        property var tileSheet: tilesLoader.item
        Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
        // (no input: the real shell under it stays usable)
        mask: Region {}

        // A bottom bar for the bottom scene: the card's hinge is its top edge.
        Block {
            visible: root.sceneName === "bottom"
            x: 0
            y: win.height - Theme.barH
            width: win.width
            height: Theme.barH
            radius: 0
            fill: Theme.surface
        }

        FormHost {
            id: host
            surface: root.sc.surface
            edge: root.sc.edge
            x: root.sc.x
            y: root.sceneName === "bottom" ? win.height - Theme.barH - root.sc.h : root.sc.y
            width: root.sc.w
            height: root.sc.h
            origin: root.sc.ox >= 0 ? Qt.rect(root.sc.ox - root.sc.x, root.sc.edge === "bottom" ? root.sc.h : -24, root.sc.ow, 24)
                : Qt.rect(0, 0, 0, 0)
            progress: root.driven ? driver.value : root.held

            Block {
                id: card
                anchors.fill: parent
                radius: Theme.rLg
                fill: Qt.alpha(Theme.surface, Theme.panel.a)
                Column {
                    x: 22
                    y: 18
                    width: card.width - 44
                    spacing: 10
                    visible: root.sceneName !== "toast"
                    Text {
                        text: root.sceneName === "sidebar" || root.sceneName === "right" ? "Notebook" : "Session"
                        color: Theme.fg
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Paper remembers every fold: a crease is light on one side and shade on the other, and the line between them is sharp."
                        color: Theme.fg
                        opacity: 0.8
                        font.pixelSize: 15
                    }
                    Repeater {
                        model: Math.max(2, Math.floor((card.height - 140) / 58))
                        Block {
                            width: parent.width
                            height: 48
                            radius: Theme.rSm
                            fill: index % 3 === 0 ? Theme.selected : Theme.containerHigh
                            Row {
                                x: 14
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 12
                                Rectangle { width: 22; height: 22; radius: 11; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: ["Lock", "Suspend", "Log out", "Restart", "Shut down", "Wi-Fi", "Bluetooth", "Night light",
                                           "Do not disturb", "Keyboard", "Displays", "Sound", "Power", "About", "Calendar", "Notes"][index % 16]
                                    color: Theme.fg
                                    font.pixelSize: 15
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }
                Row {
                    visible: root.sceneName === "toast"
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14
                    Rectangle { width: 48; height: 48; radius: 12; color: Theme.accent }
                    Column {
                        spacing: 4
                        Text { text: "Tea is ready"; color: Theme.fg; font.pixelSize: 16; font.weight: Font.DemiBold }
                        Text { text: "Sencha, 3 minutes at 70 °C — pour it now."; color: Theme.fg; opacity: 0.75; font.pixelSize: 14 }
                    }
                }
            }
        }
    }
    Component.onCompleted: log("up scene=" + sceneName)
}
