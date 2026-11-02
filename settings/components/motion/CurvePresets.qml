import QtQuick
import "../../core"
import ".."
import "curvemath.js" as CM

// The curve editor's Presets tab (brief §4): every built-in curve as a small plot with its name; a pick writes the preset's
// id (one change). Keyboard as a radio group: Tab enters at the chosen one, arrows move (Up and Down by a row), Return or
// Space picks. calm and lively are the shell's own springs (K42 units): listed and pickable, drawn as a note, not a plot.
// The list is curvemath.js's copy of kurashi-motion's presets until the daemon publishes its list, with the user's saved
// curves (CONTRACT-CHANGE, W59.6).
Column {
    id: pr
    property string key: ""
    property string current: ""
    property bool enabled: true
    signal picked(string id)
    spacing: Theme.gap

    readonly property int tileW: 104
    readonly property int cols: Math.max(1, Math.floor((width + Theme.gap) / (tileW + Theme.gap)))
    function focusAt(i) {
        var it = rep.itemAt(Math.max(0, Math.min(CM.PRESETS.length - 1, i)))
        if (it) it.forceActiveFocus()
    }
    readonly property int chosenIndex: {
        for (var i = 0; i < CM.PRESETS.length; i++) if (CM.PRESETS[i].id === pr.current) return i
        return -1
    }

    Flow {
        width: parent.width
        spacing: Theme.gap
        Accessible.role: Accessible.List
        Repeater {
            id: rep
            model: CM.PRESETS
            delegate: RoundBox {
                id: tile
                required property var modelData
                required property int index
                readonly property bool on: modelData.id === pr.current
                readonly property string name: I18n.tr("config.choice.curve." + modelData.id)
                objectName: "curve-preset:" + pr.key + ":" + modelData.id
                width: pr.tileW
                height: 72
                radius: Theme.rSm
                color: on ? Theme.container : Theme.containerHigh
                border.width: on ? 2 : 1
                border.color: on ? Theme.accent : Theme.outline
                activeFocusOnTab: pr.enabled && (on || (pr.chosenIndex < 0 && index === 0))
                Accessible.role: Accessible.RadioButton
                Accessible.name: tile.name + (modelData.ms > 0 ? ", " + modelData.ms + " ms" : "")
                Accessible.checked: on
                Keys.onLeftPressed: event => { pr.focusAt(index - 1); event.accepted = true }
                Keys.onRightPressed: event => { pr.focusAt(index + 1); event.accepted = true }
                Keys.onUpPressed: event => { pr.focusAt(index - pr.cols); event.accepted = true }
                Keys.onDownPressed: event => { pr.focusAt(index + pr.cols); event.accepted = true }
                Keys.onReturnPressed: event => { if (pr.enabled) pr.picked(modelData.id); event.accepted = true }
                Keys.onEnterPressed: event => { if (pr.enabled) pr.picked(modelData.id); event.accepted = true }
                Keys.onSpacePressed: event => { if (pr.enabled) pr.picked(modelData.id); event.accepted = true }

                Canvas {
                    id: thumb
                    x: 8; y: 6
                    width: tile.width - 16
                    height: 40
                    renderStrategy: Canvas.Cooperative
                    // Repainted only when the colours change: each thumbnail is drawn once (Ma).
                    property color ink: tile.on ? Theme.accent : Theme.fg
                    onInkChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var c = tile.modelData.curve
                        if (c.kind === "spring_q") return
                        var span = CM.spanOf(c, tile.modelData.ms)
                        // y −0.6 … 1.45: the overshoots and pull-backs of the presets fit (pudding, anticipate).
                        var X = function (x) { return x * width }
                        var Y = function (y) { return height - (y + 0.6) / 2.05 * height }
                        ctx.strokeStyle = Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.25)
                        ctx.lineWidth = 1
                        ctx.beginPath(); ctx.moveTo(X(0), Y(1)); ctx.lineTo(X(1), Y(1)); ctx.stroke()
                        ctx.strokeStyle = ink
                        ctx.lineWidth = 2
                        ctx.beginPath()
                        ctx.moveTo(X(0), Y(0))
                        for (var i = 1; i <= 48; i++) ctx.lineTo(X(i / 48), Y(CM.sample(c, i / 48, span)))
                        ctx.stroke()
                    }
                }
                MotionText {
                    visible: tile.modelData.curve.kind === "spring_q"
                    anchors.centerIn: thumb
                    small: true
                    color: Theme.dim
                    text: I18n.tr("motion.ui.curve.own_spring_short")
                }
                MotionText {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 8
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    small: true
                    font.weight: tile.on ? Font.DemiBold : Font.Normal
                    text: (tile.on ? "✓ " : "") + tile.name
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: pr.enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pr.picked(tile.modelData.id)
                }
                FocusRing {
                    anchors.fill: parent
                    shown: tile.activeFocus
                    corner: Theme.rSm
                }
            }
        }
    }
    MotionText {
        width: parent.width
        small: true
        color: Theme.dim
        text: I18n.tr("motion.ui.curve.user_presets")
    }
}
