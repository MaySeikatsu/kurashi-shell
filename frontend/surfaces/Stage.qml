import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"

// Stage (ARCHITECTURE §4): overlay layer surface holding popups / OSD / island expansions and the
// session menu. Sized to its content (K16: a full-output buffer cost ~80 MiB), top-centred under the
// Island. One instance, retargeted by shell.qml to the focused output. Later OSD/toasts: grow the
// implicit size to the union of their cards, or add sibling content-sized Stages; never a full-output one.
//
// Idle = silent (Ma) without unmapping: map/unmap cycles of this window left ~5 MiB of heap behind
// per cycle (measured, K16), a permanently mapped, fully transparent, input-less surface costs
// nothing (0 renders, 0 commits; the compositor just skips it). Hidden = card not visible, empty
// input and blur regions, no keyboard focus. Reveal starts on the first presented frame.
PanelWindow {
    id: stage

    // Island panel or session menu is open. shell.qml sets it after it picked the output.
    property bool want: false
    // Which of the two the card shows comes from runtime.ui.panel.
    Watch { doc: "runtime.ui" }
    readonly property bool sessionWanted: ((Store.docs["runtime.ui"] || ({})).panel) === "session"
    readonly property bool open: want || sessionWanted
    // Content the card shows. Latched while the card slides out, so a closing session menu does not
    // flash island content.
    readonly property string wantedKind: sessionWanted ? "session" : (want ? "island" : "")
    property string contentKind: "island"
    onWantedKindChanged: if (wantedKind !== "") contentKind = wantedKind
    // The card keeps the Stage's one keyboard focus across content changes (the session menu is
    // driven from it), so it takes focus back whenever the content swaps.
    onContentKindChanged: Qt.callLater(function () { card.forceActiveFocus() })

    // The bar of this output: the card sits just under a top bar, just above a bottom bar, and at
    // the screen edge otherwise (no bar, or a side bar a centred card does not meet).
    BarConfig { id: bars; screen: stage.screen }

    readonly property int slide: 12     // px the card travels while revealing
    property real p: 0                  // reveal progress 0..1
    property bool gate: false           // waiting for the first presented frame
    property bool shown: false          // card is on screen (opening, open or closing)

    // Only one vertical edge anchored -> the compositor centres the surface horizontally.
    anchors { top: !bars.atBottom; bottom: bars.atBottom }
    margins { top: bars.topInset; bottom: bars.bottomInset }
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
            // Content first: a session menu closed a moment ago must not show for a frame.
            contentKind = sessionWanted ? "session" : "island"
            anim.stop()
            if (!shown) { p = 0; gate = true; shown = true }
            else { anim.from = p; anim.to = 1; anim.start() }
        } else if (shown) {
            gate = false
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

    // ---- card under the Island: island panel (title and close), or the session menu -------------
    Rectangle {
        id: card
        visible: stage.shown
        width: 360
        height: (stage.contentKind === "session" ? menu.implicitHeight : col.implicitHeight) + 2 * (Theme.pad + 4)
        // Slide, not fade: group opacity over a text-heavy card cost ~4 MiB of retained heap (K16).
        y: -stage.slide * (1 - stage.p)   // above the surface edge = clipped away
        radius: Theme.rLg
        color: Theme.container
        border.width: 1
        border.color: Theme.outline
        // The Stage's one keyboard focus holder. The session menu is driven from here and never takes
        // focus itself (a second holder would clear this flag for good). Esc closes whichever panel.
        focus: true
        Keys.onPressed: event => {
            if (stage.contentKind === "session" && menu.handleKey(event.key)) { event.accepted = true; return }
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
            // The one close action of the island panel.
            Button { label: I18n.tr("frontend.stage.close"); primary: true; onClicked: Store.act("ui.close") }
        }

        SessionMenu {
            id: menu
            visible: stage.contentKind === "session"
            active: stage.open && stage.contentKind === "session"
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.pad + 4 }
        }
    }
}
