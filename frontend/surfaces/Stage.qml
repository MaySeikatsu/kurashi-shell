import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"

// Stage (ARCHITECTURE §4): overlay layer surface holding popups / OSD / island expansions, the
// session menu and the tray item menus (K23). Sized to its content (K16: a full-output buffer cost
// ~80 MiB), top-centred under the Island, or hung from the bar's tray end for a tray menu. One
// instance, retargeted by shell.qml to the output that asked for it. Later OSD/toasts: grow the
// implicit size to the union of their cards, or add sibling content-sized Stages; never a full-output one.
//
// Idle = silent (Ma) without unmapping: map/unmap cycles of this window left ~5 MiB of heap behind
// per cycle (measured, K16), a permanently mapped, fully transparent, input-less surface costs
// nothing (0 renders, 0 commits; the compositor just skips it). Hidden = card not visible, empty
// input and blur regions, no keyboard focus. Reveal starts on the first presented frame.
PanelWindow {
    id: stage

    // A Stage panel is wanted (island, session menu or tray menu). shell.qml sets it after it picked the output.
    property bool want: false
    // Which one the card shows comes from runtime.ui, where the daemon keeps the open panel (K23).
    Watch { doc: "runtime.ui" }
    readonly property var ui: Store.docs["runtime.ui"] || ({})
    readonly property bool sessionWanted: ui.panel === "session"
    readonly property bool trayWanted: ui.panel === "tray"
    readonly property bool open: want
    readonly property string wantedKind: sessionWanted ? "session" : (trayWanted ? "tray" : (want ? "island" : ""))
    // Content the card shows. Latched while the card slides out, so a closing menu does not flash other content.
    property string contentKind: "island"
    onWantedKindChanged: if (wantedKind !== "") contentKind = wantedKind
    // The card keeps the Stage's one keyboard focus across content changes and reopenings (the menus
    // are driven from it), so it takes focus back whenever the content swaps or the Stage opens.
    onContentKindChanged: Qt.callLater(function () { card.forceActiveFocus() })

    // The bar of this output: the card sits just under a top bar, just above a bottom bar, and at
    // the screen edge otherwise (no bar, or a side bar a centred card does not meet).
    BarConfig { id: bars; screen: stage.screen }
    // A tray menu hangs from the tray's end of the bar: the bar's right end on a top or bottom bar,
    // the bottom end beside a side bar (the tray is the last thing in those columns).
    readonly property bool aligned: contentKind === "tray"
    readonly property bool menuBeside: aligned && bars.vertical

    readonly property int slide: 12     // px the card travels while revealing
    property real p: 0                  // reveal progress 0..1
    property bool gate: false           // waiting for the first presented frame
    property bool shown: false          // card is on screen (opening, open or closing)

    // Only one vertical edge anchored -> the compositor centres the surface horizontally.
    anchors {
        top: !bars.atBottom && !menuBeside
        bottom: bars.atBottom || menuBeside
        left: menuBeside && bars.edge === "left"
        right: aligned && (!bars.vertical || bars.edge === "right")
    }
    margins {
        top: bars.topInset
        bottom: menuBeside ? Theme.pad : bars.bottomInset
        left: menuBeside ? Theme.barH + Theme.gap : 0
        right: aligned ? (menuBeside ? Theme.barH + Theme.gap : Theme.pad) : 0
    }
    implicitWidth: card.width
    implicitHeight: card.height
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "kurashi-stage"
    color: "transparent"
    mask: shown ? cardRegion : emptyRegion
    BackgroundEffect.blurRegion: shown ? cardRegion : emptyRegion
    Region { id: cardRegion; item: card }
    Region { id: emptyRegion }

    onOpenChanged: {
        if (open) {
            // Content first: a menu closed a moment ago must not show for a frame.
            contentKind = wantedKind === "" ? "island" : wantedKind
            Qt.callLater(function () { card.forceActiveFocus() })
            anim.stop()
            if (!shown) { p = 0; gate = true; shown = true }
            else { anim.from = p; anim.to = 1; anim.start() }
        } else if (shown) {
            gate = false
            btErr = ""
            anim.stop(); anim.from = p; anim.to = 0; anim.start()
        }
    }
    NumberAnimation {
        id: anim
        target: stage; property: "p"
        duration: Theme.stdMs
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve
        onFinished: if (stage.p <= 0 && !stage.open) stage.shown = false
    }
    Connections {
        target: card.Window.window
        function onFrameSwapped() {
            if (stage.gate) { stage.gate = false; anim.from = stage.p; anim.to = 1; anim.start() }
        }
    }

    // Watched only while their content is on screen (Ma): a hidden card holds no subscription.
    // Bluetooth is BlueZ's service; the tray menu reads its item's title from svc.tray.
    readonly property var bluetooth: Store.docs["svc.bluetooth"] || ({})
    readonly property bool islandLive: shown && contentKind === "island"
    readonly property bool trayLive: shown && contentKind === "tray"
    Watch { doc: "svc.bluetooth"; active: stage.islandLive }
    Watch { doc: "svc.tray"; active: stage.trayLive }

    // ---- Bluetooth requests from the island panel. A refused one shows a translated line ----------
    property string btErr: ""
    function btAct(action, args) {
        btErr = ""
        Store.act(action, args, function (done, err) {
            if (err) stage.btErr = stage.errorText(err, "frontend.bt.failed")
        })
    }

    // A failed action shows its translated text, never the daemon's raw msg: msg is an i18n key
    // (error.*). A key without text falls back to the panel's own line.
    function errorText(err, fallback) {
        var k = err && err.msg ? String(err.msg) : ""
        var t = k === "" ? "" : I18n.tr(k)
        return (t !== "" && t !== k) ? t : I18n.tr(fallback)
    }

    // ---- Tray item menus (K23). The daemon names the item (runtime.ui.tray); its tree is fetched
    // once per open, as action data, and drawn by TrayMenu. A newer open supersedes an older fetch.
    readonly property string trayKey: trayWanted ? String(ui.tray || "") : ""
    property var trayTree: null
    property string trayErr: ""
    property int trayReq: 0
    onTrayKeyChanged: loadTray()
    function loadTray() {
        var req = ++trayReq
        trayTree = null
        trayErr = ""
        trayMenu.cursor = -1
        trayMenu.expanded = ({})
        if (trayKey === "") return
        Store.act("tray.menu", {id: trayKey}, function (done, err) {
            if (req !== stage.trayReq || stage.trayKey === "") return   // superseded, or closed meanwhile
            if (err) stage.trayErr = stage.errorText(err, "frontend.tray.failed")
            else stage.trayTree = done.data || ({children: []})
        })
    }
    // The item the menu belongs to (title and tooltip come from svc.tray), or an empty object.
    function trayItem(id) {
        var items = (Store.docs["svc.tray"] || ({})).items || []
        for (var i = 0; i < items.length; i++) if (items[i].id === id) return items[i]
        return ({})
    }
    // The tooltip without its first line (the title, already shown), one line for the heading below.
    function trayTipText(id) {
        var it = trayItem(id)
        return String(it.tooltip || "").split("\n").filter(function (l) { return l !== "" && l !== it.title }).join(" · ")
    }

    // ---- card under the Island: island panel (title, Bluetooth, close), session menu, or tray menu
    Rectangle {
        id: card
        visible: stage.shown
        width: 360
        height: (stage.contentKind === "island" ? col.implicitHeight
            : stage.contentKind === "session" ? menu.implicitHeight : trayCol.implicitHeight) + 2 * (Theme.pad + 4)
        // Slide, not fade: group opacity over a text-heavy card cost ~4 MiB of retained heap (K16).
        y: -stage.slide * (1 - stage.p)   // above the surface edge = clipped away
        radius: Theme.rLg
        color: Theme.container
        border.width: 1
        border.color: Theme.outline
        // The Stage's one keyboard focus holder. The menus are driven from here and never take
        // focus themselves (a second holder would clear this flag for good). Esc closes whichever panel.
        focus: true
        Keys.onPressed: event => {
            if (stage.contentKind === "session" && menu.handleKey(event.key)) { event.accepted = true; return }
            if (stage.contentKind === "tray" && trayMenu.handleKey(event.key)) { event.accepted = true; return }
            if (event.key === Qt.Key_Escape) { Store.act("ui.close"); event.accepted = true }
        }

        Column {
            id: col
            visible: stage.contentKind === "island"
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.pad + 4 }
            spacing: Theme.pad
            Text {
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("frontend.stage.title")
            }
            // Visible only while the daemon serves svc.bluetooth (no BlueZ, nothing to show).
            BluetoothPanel {
                width: col.width
                visible: stage.bluetooth.available === true
                doc: stage.bluetooth
                errText: stage.btErr
                onPowerRequested: on => stage.btAct("bluetooth.power", {on: on})
                onScanRequested: on => stage.btAct("bluetooth.scan", {on: on})
                onLinkRequested: (address, connect) =>
                    stage.btAct(connect ? "bluetooth.connect" : "bluetooth.disconnect", {address: address})
            }
            // The one close action of the island panel.
            Button { label: I18n.tr("frontend.stage.close"); primary: true; onClicked: Store.act("ui.close") }
        }

        SessionMenu {
            id: menu
            visible: stage.contentKind === "session"
            active: stage.open && stage.contentKind === "session"
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.pad + 4 }
        }

        Column {
            id: trayCol
            visible: stage.contentKind === "tray"
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.pad + 4 }
            spacing: Theme.gap
            Text {
                width: trayCol.width
                elide: Text.ElideRight
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                font.family: Theme.fam(text, Theme.families)
                text: stage.trayItem(stage.trayKey).title || I18n.tr("frontend.tray.menu")
            }
            Text {
                visible: text !== ""
                width: trayCol.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: stage.trayTipText(stage.trayKey)
            }
            TrayMenu {
                id: trayMenu
                width: trayCol.width
                tree: stage.trayTree
                errText: stage.trayErr
                onChosen: item => {
                    Store.act("tray.menu_event", {id: stage.trayKey, item: item})
                    Store.act("ui.close")
                }
            }
        }
    }
}
