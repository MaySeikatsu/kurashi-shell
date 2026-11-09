import QtQuick
import qs.core
import qs.components
import "Timer.js" as T

// Bar widget of the timer mod (K73, docs/ux/timer.md "Glance"): a ring and the time left of the nearest timer (h:mm from an
// hour up); paused, the time it kept, dimmed; ended, an alarm in the accent colour; with no timer, the timer glyph alone.
// A click (Return, Enter, Space too) starts the default countdown, or opens the panel while a timer is on. The wheel adds or
// takes a minute from the nearest. Visible = subscribed (Ma): the
// second clock runs only while a running countdown shows.
Item {
    // Handed in by ModLoader (K26 loader contract).
    required property var store
    required property var theme
    required property var i18n
    id: w
    property bool vertical: false

    property bool live: visible
    Watch { doc: "mod.timer"; active: w.live }

    readonly property var d: Store.docs["mod.timer"] || ({})
    readonly property var nearest: T.nearest(d.timers)
    readonly property bool showing: nearest !== null && nearest !== undefined
    readonly property bool running: showing && nearest.state === "running"
    readonly property bool paused: showing && nearest.state === "paused"
    readonly property bool ended: showing && nearest.state === "ended"
    // A pomodoro's break: its arc takes the tertiary colour, a focus the accent.
    readonly property bool onBreak: showing && nearest.kind === "pomodoro" && nearest.phase !== "focus"

    Tick { id: clock; wanted: w.visible && w.running }
    readonly property string timeText: showing && !ended ? T.clock(T.left(nearest, clock.now)) : ""
    readonly property real share: running || paused ? T.share(nearest, clock.now) : 0
    readonly property string shownName: showing ? T.nameOf(nearest, nearest.kind === "pomodoro" ? I18n.tr("mod-timer.name.pomodoro") : I18n.tr("mod-timer.name.timer")) : ""

    function primary() {
        if (w.showing) Store.act("mod.panel.open", { id: "timer", panel: "timer" }, function () {})
        else Store.act("timer.start", {}, function () {})
    }
    function nudge(up) {
        if (w.showing) Store.act("timer.add", { id: w.nearest.id, minutes: up ? 1 : -1 }, function () {})
    }

    // B48 (docs/ux/bar-fit.md, the widget's fit): compact — a crowded bar — the ring alone; the time left stays the
    // accessible name. The widths from metrics (a hidden text is not laid out).
    property bool compact: false
    readonly property bool timeShown: w.showing && !w.ended && !w.compact
    TextMetrics { id: timeM; text: w.showing && !w.ended ? w.timeText : ""; font.pixelSize: Theme.fs; font.family: Theme.fam(text, Theme.families); font.features: ({"tnum": 1}) }
    readonly property real markW: w.showing && !w.ended ? Math.round(Theme.iconSize * Theme.iconScale) : timerIcon.implicitWidth
    readonly property real fullWidth: markW + (w.showing && !w.ended ? Theme.xs + Math.ceil(timeM.advanceWidth) : 0) + Theme.gap * 2
    readonly property real compactWidth: markW + Theme.gap * 2
    implicitWidth: w.vertical ? Theme.barH : row.implicitWidth + Theme.gap * 2
    implicitHeight: w.vertical ? col.implicitHeight : Theme.controlH
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: !w.showing ? I18n.tr("mod-timer.widget.a11y.idle")
        : w.ended ? I18n.tr("mod-timer.face.ended")
        : T.fill(I18n.tr("mod-timer.widget.a11y.running"), { label: w.shownName, time: w.timeText })
    Keys.onReturnPressed: w.primary()
    Keys.onEnterPressed: w.primary()
    Keys.onSpacePressed: w.primary()

    Row {
        id: row
        visible: !w.vertical
        anchors.centerIn: parent
        spacing: Theme.xs
        Ring {
            visible: w.showing && !w.ended
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(Theme.iconSize * Theme.iconScale)
            height: width
            share: w.share
            stroke: w.paused ? Theme.dim : (w.onBreak ? Theme.tertiary : Theme.accent)
            track: Theme.outline
        }
        Icon {
            id: timerIcon
            visible: !w.showing || w.ended
            anchors.verticalCenter: parent.verticalCenter
            name: w.ended ? "alarm" : "timer"
            glyph: "⏱"
            color: w.ended ? Theme.accent : Theme.fg
        }
        Text {
            visible: w.timeShown
            anchors.verticalCenter: parent.verticalCenter
            color: w.paused ? Theme.dim : Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            font.features: ({"tnum": 1})
            text: w.timeText
        }
    }
    Column {
        id: col
        visible: w.vertical
        anchors.centerIn: parent
        spacing: Theme.xs
        Ring {
            visible: w.showing && !w.ended
            anchors.horizontalCenter: parent.horizontalCenter
            width: Theme.barH - 12
            height: Theme.barH - 12
            share: w.share
            stroke: w.paused ? Theme.dim : (w.onBreak ? Theme.tertiary : Theme.accent)
            track: Theme.outline
        }
        Icon {
            visible: !w.showing || w.ended
            anchors.horizontalCenter: parent.horizontalCenter
            name: w.ended ? "alarm" : "timer"
            glyph: "⏱"
            color: w.ended ? Theme.accent : Theme.fg
        }
    }

    FocusRing { anchors.fill: parent; shown: w.activeFocus; corner: Theme.rSm }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: w.primary()
        onWheel: w.nudge(wheel.angleDelta.y > 0)
    }
}
