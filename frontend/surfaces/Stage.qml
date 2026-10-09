import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"

// Stage (ARCHITECTURE §4): one overlay layer surface per output holding popups / OSD / island
// expansions. Mapped only while something is visible (Ma); input region = the visible content so
// the rest of the screen stays click-through; reveal starts on the first presented frame.
PanelWindow {
    id: stage
    required property var modelData
    screen: modelData

    readonly property bool want: Store.ui && Store.ui.popup === true
    property real p: 0                  // reveal progress 0..1
    property bool gate: false           // waiting for the first presented frame

    anchors { top: true; left: true; right: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: want ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "kurashi-stage"
    color: "transparent"
    visible: false
    mask: Region { item: card }
    BackgroundEffect.blurRegion: Region { item: card }

    onWantChanged: {
        if (want) {
            anim.stop()
            if (!visible) { p = 0; gate = true; visible = true }
            else { anim.from = p; anim.to = 1; anim.start() }
        } else if (visible) {
            gate = false
            anim.stop(); anim.from = p; anim.to = 0; anim.start()
        }
    }
    NumberAnimation {
        id: anim
        target: stage; property: "p"
        duration: Theme.stdMs
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve
        onFinished: if (stage.p <= 0 && !stage.want) stage.visible = false
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
        width: 360
        height: col.implicitHeight + 2 * (Theme.pad + 4)
        x: (stage.width - width) / 2
        y: Theme.barH + 4
        opacity: stage.p
        scale: 0.96 + 0.04 * stage.p
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
