import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"
import "../components/island"

// The OSD (session 33, I527; docs/ux/osd.md): the answer to a key that changed the volume, the microphone, the brightness
// or the keyboard layout — one pill in the look, on the focused output, for `osd.timeout_ms`. The daemon decides what shows
// and where (`runtime.osd`, crates/kurashid/src/osd.rs); this draws it. A held key is one OSD that follows (each event
// restarts the timeout). It never takes input; hidden, it has no window (Ma).
PanelWindow {
    id: osd
    Watch { doc: "runtime.osd" }
    readonly property var d: Store.docs["runtime.osd"] || ({})
    readonly property int seq: d.seq !== undefined ? d.seq : -1
    readonly property string kind: d.kind || ""
    readonly property string place: d.place || "bottom"
    readonly property bool hasLevel: d.value !== undefined && d.value !== null
    readonly property real level: hasLevel ? Math.max(0, Math.min(1, Number(d.value))) : 0
    readonly property bool muted: d.muted === true

    // (the first document a start reads is no event)
    property int seenSeq: -2
    property bool up: false
    onSeqChanged: {
        if (seenSeq === -2) { seenSeq = seq; return }
        if (seq === seenSeq || seq < 0) return
        seenSeq = seq
        up = true
        hold.interval = Math.max(600, d.timeout_ms || 1500)
        hold.restart()
    }
    Component.onCompleted: if (seq >= 0) seenSeq = seq
    Timer { id: hold; onTriggered: osd.up = false }

    // Shown: in while up, out after; unmapped once out (no frames, Ma).
    Glide { id: shown; to: osd.up ? 1 : 0 }
    readonly property real s: Math.max(0, Math.min(1, shown.value))
    visible: osd.up || s > 0.005

    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "kurashi-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Input passes through: nothing here takes a click.
    mask: Region {}
    anchors.bottom: place === "bottom"
    anchors.top: place === "top"
    margins.bottom: place === "bottom" ? 72 : 0
    margins.top: place === "top" ? 16 : 0
    implicitWidth: kind === "layout" ? 280 : 340
    implicitHeight: kind === "layout" ? 88 : 64

    readonly property string title: kind === "volume" ? (muted ? I18n.tr("osd.muted") : I18n.tr("osd.volume"))
        : kind === "mic" ? I18n.tr(muted ? "osd.mic_muted" : "osd.mic_on")
        : kind === "brightness" ? I18n.tr("osd.brightness")
        : kind === "layout" || kind === "custom" ? String(d.label || "") : ""
    readonly property string sub: d.sub !== undefined ? String(d.sub)
        : kind === "volume" || kind === "mic" ? String(d.label || "")
        : kind === "layout" ? I18n.tr("osd.layout") : ""
    readonly property string announceText: title + (hasLevel ? " " + Math.round(level * 100) + " %" : "")

    Block {
        id: pill
        anchors.centerIn: parent
        width: parent.width - 16
        height: parent.height - 8 - Theme.shadowDy
        radius: Math.min(Theme.rFull, height / 2)
        fill: Theme.surface
        opacity: osd.s
        scale: 0.94 + 0.06 * osd.s
        Accessible.role: Accessible.AlertMessage
        Accessible.name: osd.announceText

        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 18
            spacing: 14
            width: parent.width - 36
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: String(osd.d.icon || "")
                glyph: osd.kind === "layout" ? "⌨" : "●"
                size: osd.kind === "layout" ? 30 : 24
                color: osd.muted ? Theme.dim : Theme.fg
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 24 - 14 - (pct.visible ? pct.width + 14 : 0) - (cap.visible ? cap.width + 14 : 0)
                spacing: 5
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    color: Theme.fg
                    font.pixelSize: osd.kind === "layout" ? Theme.fsTitle : Theme.fs
                    font.weight: Theme.wBold
                    font.family: Theme.fam(text, Theme.families)
                    text: osd.title
                }
                LevelMeter {
                    visible: osd.hasLevel
                    width: parent.width
                    level: osd.level
                    animate: Theme.springOn
                    color: osd.muted ? Theme.dim : Theme.accent
                }
                Text {
                    visible: osd.sub !== "" && (!osd.hasLevel || osd.kind === "mic")
                    width: parent.width
                    elide: Text.ElideRight
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: osd.sub
                }
            }
            Text {
                id: pct
                visible: osd.hasLevel
                anchors.verticalCenter: parent.verticalCenter
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                color: osd.muted ? Theme.dim : Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                font.features: { "tnum": 1 }
                text: Math.round(osd.level * 100) + " %"
            }
            Rectangle {
                id: cap
                visible: osd.kind === "layout" && !!osd.d.short
                anchors.verticalCenter: parent.verticalCenter
                width: capText.implicitWidth + 18
                height: 32
                radius: Theme.rSm + 2
                color: Theme.containerHigh
                border.width: 1
                border.color: Theme.outline
                Text {
                    id: capText
                    anchors.centerIn: parent
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    color: Theme.fg
                    font.pixelSize: Theme.fs + 2
                    font.weight: Theme.wBold
                    font.family: Theme.fam(text, Theme.families)
                    text: String(osd.d.short || "")
                }
            }
        }
    }
}
