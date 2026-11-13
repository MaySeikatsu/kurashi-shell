import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components/menus"

// A click elsewhere closes what a click opened (I279: no Close buttons; Esc does the same). While a Stage card, the
// launcher, the notification centre or a tray menu is open, one transparent window per output over the usable area takes
// a press and runs `ui.close`. A layer surface sees no click outside itself and niri gives layer surfaces no focus grab,
// so the catcher is the click (as the toggled sidebar's, I152). It sits on the top layer, under the popups (overlay)
// and over the apps; placed in the usable area (exclusive zones respected), it leaves the bars and the frame their
// clicks — a bar widget still opens its own card. No window while nothing is open (Ma); none under a polkit dialog,
// which keeps the panels shut itself.
Scope {
    id: ca
    required property var modelData

    Watch { doc: "runtime.ui" }
    readonly property var ui: Store.docs["runtime.ui"] || ({})
    // (session 31, `ui.keep`: a card kept open — `kept` names the open panel — lets clicks elsewhere through)
    readonly property bool kept: (ui.kept || "") !== "" && ui.kept === ui.panel && ui.launcher !== true && (ui.tray || "") === ""
    // (W82: no window on this output's workspace — `tasks`, watched by shell.qml — so all under this window is the desktop)
    readonly property bool desktopOnly: {
        var t = (Store.docs["svc.workspaces"] || {}).tasks
        var l = t && modelData ? t[modelData.name] : null
        return Array.isArray(l) && l.length === 0
    }
    readonly property bool open: ui.polkit !== true && !kept
        && ((ui.panel || "") !== "" || ui.launcher === true || (ui.tray || "") !== "")

    LazyLoader {
        active: ca.open
        PanelWindow {
            screen: ca.modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "kurashi-clickaway"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            // B117 (session 29, the user: the web dock's edge should reveal on hover while a card is open): an edge
            // whose hover zone asks for it (EdgeStrips.setClear) keeps its outer 2 px out of this window's input, so
            // the zone under it still sees the pointer. A press there closes nothing.
            readonly property string outName: ca.modelData ? ca.modelData.name : ""
            mask: Region {
                item: catcher
                Region { intersection: Intersection.Subtract; x: 0; y: 0; width: catcher.width; height: EdgeStrips.clearOn(outName, "top") ? 2 : 0 }
                Region { intersection: Intersection.Subtract; x: 0; y: catcher.height - 2; width: catcher.width; height: EdgeStrips.clearOn(outName, "bottom") ? 2 : 0 }
                Region { intersection: Intersection.Subtract; x: 0; y: 0; width: EdgeStrips.clearOn(outName, "left") ? 2 : 0; height: catcher.height }
                Region { intersection: Intersection.Subtract; x: catcher.width - 2; y: 0; width: EdgeStrips.clearOn(outName, "right") ? 2 : 0; height: catcher.height }
            }
            MouseArea {
                id: catcher
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: mouse => {
                    // W82 (docs/ux/context-menus.md): a right click where only the desktop is (no window on this output's
                    // workspace) opens the desktop's menu there, as desktops do; anything else closes what is open.
                    if (mouse.button === Qt.RightButton && ca.desktopOnly) {
                        var z = function (e) { var x = (ShellLayout.of(outName).edges || {})[e] || {}; return x.holder && x.holder !== "none" && typeof x.reserve === "number" ? x.reserve : 0 }
                        MenuAt.open("desktop:" + outName, outName, z("left") + mouse.x, z("top") + mouse.y)
                    } else Store.act("ui.close")
                }
            }
        }
    }
}
