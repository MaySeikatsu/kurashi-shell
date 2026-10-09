import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"

// Stage (ARCHITECTURE §4): overlay layer surface holding popups / OSD / island expansions.
// Sized to its content (K16: a full-output buffer cost ~80 MiB), top-centred under the Island.
// One instance, retargeted by shell.qml to the focused output. Later OSD/toasts: grow the implicit
// size to the union of their cards, or add sibling content-sized Stages; never a full-output one.
//
// Idle = silent (Ma) without unmapping: map/unmap cycles of this window left ~5 MiB of heap behind
// per cycle (measured, K16), a permanently mapped, fully transparent, input-less surface costs
// nothing (0 renders, 0 commits; the compositor just skips it). Hidden = card not visible, empty
// input and blur regions, no keyboard focus. Reveal starts on the first presented frame.
PanelWindow {
    id: stage

    property bool want: false           // set by shell.qml after it picked the output
    readonly property int slide: 12     // px the card travels while revealing
    property real p: 0                  // reveal progress 0..1
    property bool gate: false           // waiting for the first presented frame
    property bool shown: false          // card is on screen (opening, open or closing)

    // Only top anchored -> the compositor centres the surface horizontally.
    anchors { top: true }
    margins { top: Theme.barH + 4 }
    implicitWidth: card.width
    implicitHeight: card.height
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: want ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "kurashi-stage"
    color: "transparent"
    mask: shown ? cardRegion : emptyRegion
    BackgroundEffect.blurRegion: shown ? cardRegion : emptyRegion
    Region { id: cardRegion; item: card }
    Region { id: emptyRegion }

    onWantChanged: {
        if (want) {
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
        onFinished: if (stage.p <= 0 && !stage.want) stage.shown = false
    }
    Connections {
        target: card.Window.window
        function onFrameSwapped() {
            if (stage.gate) { stage.gate = false; anim.from = stage.p; anim.to = 1; anim.start() }
        }
    }

    // ---- popup card, anchored under the Island ----------------------------------------------
    Rectangle {
        id: card
        visible: stage.shown
        width: 360
        height: col.implicitHeight + 2 * (Theme.pad + 4)
        // Slide, not fade: group opacity over a text-heavy card cost ~4 MiB of retained heap (K16).
        y: -stage.slide * (1 - stage.p)   // above the surface edge = clipped away
        radius: Theme.rLg
        color: Theme.container
        border.width: 1
        border.color: Theme.outline
        focus: true
        Keys.onEscapePressed: Store.act("probe.popup.toggle")

        Column {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.pad + 4 }
            spacing: Theme.pad
            Text {
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("frontend.stage.title")
            }
            Rectangle {
                width: parent.width; height: 32
                radius: Theme.rSm
                color: Theme.surface
                border.width: 1
                border.color: field.activeFocus ? Theme.accent : Theme.outline
                TextInput {
                    id: field
                    anchors { fill: parent; margins: 6 }
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    Keys.onEscapePressed: Store.act("probe.popup.toggle")
                }
            }
            // Static sample until the daemon serves cfg.* (Provenanced values).
            ProvenanceChip {
                prov: ({ value: "42%", source: "default" })
            }
            ProvenanceChip {
                prov: ({ value: "dark", source: "profile", forced_by: "profile:presentation", reason: "sample" })
            }
            Row {
                spacing: Theme.gap
                Button { label: I18n.tr("frontend.stage.close"); primary: true; onClicked: Store.act("probe.popup.toggle") }
                IconButton { glyph: "✕"; a11y: I18n.tr("frontend.stage.close"); onClicked: Store.act("probe.popup.toggle") }
            }
        }
    }
}
