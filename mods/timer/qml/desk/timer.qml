import QtQuick
import qs.core
import qs.components
import ".."
import "../Timer.js" as T

// The timer card on the desk (K73, docs/ux/timer.md "Desk card"): the pomodoro's ring, large, with its phase and round, or the
// nearest countdown's ring and time; with no timer running, the presets to start one. The desk has no keyboard focus (K43):
// the card is clicked, and a click on a timer opens the panel. Visible = the desk is shown (Ma); the clock runs only while a
// countdown runs.
Item {
    // Handed in by ModLoader (K26 loader contract).
    required property var store
    required property var theme
    required property var i18n
    id: dc

    // The card lives while the desk is shown (its ModLoader is gated on that), so it watches for its lifetime.
    Watch { doc: "mod.timer" }

    readonly property var d: Store.docs["mod.timer"] || ({})
    readonly property var timers: d.timers || []
    readonly property var presets: d.presets || []
    readonly property var pomodoro: T.first(timers, "pomodoro")
    readonly property var focus: pomodoro !== null ? pomodoro : T.nearest(timers)
    readonly property bool shown: focus !== null && focus !== undefined
    readonly property bool anyRunning: T.runningCount(timers) > 0

    Tick { id: clock; wanted: dc.visible && dc.anyRunning }

    width: parent ? parent.width : 300
    implicitHeight: card.height

    function tr(key) { return I18n.tr(key) }
    function start(minutes) {
        if (d.background === false) Store.act("mod.panel.open", { id: "timer", panel: "timer" }, function () {})
        else Store.act("timer.start", { minutes: minutes }, function () {})
    }

    Block {
        id: card
        width: dc.width
        height: body.implicitHeight + 2 * Theme.pad + Theme.shadowDy
        radius: Theme.rLg + 4
        fill: Theme.surfaceAlpha
        flatBorder: Theme.outline

        // Under the content, so the presets and the text stay clickable; a click on the bare card opens the panel.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            enabled: dc.shown
            onClicked: Store.act("mod.panel.open", { id: "timer", panel: "timer" }, function () {})
        }

        Column {
            id: body
            x: Theme.pad
            y: Theme.pad
            width: card.width - 2 * Theme.pad
            spacing: Theme.gap

            Text {
                width: parent.width
                text: dc.tr("mod-timer.desk.title")
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            Row {
                visible: dc.shown
                width: parent.width
                spacing: Theme.gap
                Ring {
                    width: dc.pomodoro !== null ? 72 : 56
                    height: width
                    anchors.verticalCenter: parent.verticalCenter
                    share: T.share(dc.focus, clock.now)
                    stroke: dc.focus !== null && dc.focus.state === "paused" ? Theme.dim : Theme.fg
                    track: Theme.outline
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 72 - Theme.gap
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: dc.focus === null ? ""
                            : dc.focus.kind === "pomodoro" ? T.fill(dc.tr("mod-timer.panel.round"), {n: dc.focus.round, rounds: dc.focus.rounds})
                            : T.nameOf(dc.focus, dc.tr("mod-timer.name.timer"))
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                    }
                    Text {
                        text: dc.focus === null ? ""
                            : dc.focus.state === "ended" ? dc.tr("mod-timer.panel.ended")
                            : dc.focus.state === "paused" ? T.clock(dc.focus.remaining_ms)
                            : T.clock(T.left(dc.focus, clock.now))
                        color: dc.focus !== null && dc.focus.state === "ended" ? Theme.accent : Theme.fg
                        font.pixelSize: Theme.fsDisplay
                        font.weight: Theme.wMedium
                        font.features: ({"tnum": 1})
                        font.family: Theme.fam(text, Theme.families)
                    }
                }
            }

            Flow {
                visible: !dc.shown
                width: parent.width
                spacing: Theme.gap
                Text {
                    width: parent.width
                    text: dc.tr("mod-timer.desk.idle")
                    color: Theme.dim
                    font.pixelSize: Theme.fsLabel
                    font.family: Theme.fam(text, Theme.families)
                }
                Repeater {
                    model: dc.presets
                    delegate: Button {
                        required property var modelData
                        label: T.fill(dc.tr("mod-timer.panel.preset"), {min: modelData})
                        onClicked: dc.start(modelData)
                    }
                }
            }
        }

    }
}
