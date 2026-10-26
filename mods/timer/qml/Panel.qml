import QtQuick
import qs.core
import qs.components
import "Timer.js" as T

// Panel of the timer mod (K73, docs/ux/timer.md "Expanded / sidebar"). The Stage card hosts it, and so does a sidebar section
// (the same file, a fixed width, `fillHeight` and `placement` unused here). Top to bottom: the running countdowns (ring, name,
// time left, pause or resume, +1 min, stop; an ended one says its time is up, and +1 min starts it again), the presets as
// buttons, a custom length ("mm" or "mm:ss", Enter starts), and the pomodoro card (phase, round, time, pause or resume, next
// phase, reset). Every change is an action; a refusal is an i18n key, shown under the part that asked. Space pauses or resumes
// the focused countdown. Visible while open: the second clock runs only while a countdown runs (Ma).
Item {
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n
    id: p

    Watch { doc: "mod.timer" }

    property real fillHeight: 0
    // A sidebar section sets the rect at rest here (the sidebar's Placement, W30); the width comes from the parent, as the tasks
    // panel's does: the Stage card and the sidebar section both give the panel their width.
    property var placement: null
    property int cardWidth: 400
    width: parent ? parent.width : cardWidth
    implicitHeight: body.implicitHeight

    readonly property var d: Store.docs["mod.timer"] || ({})
    readonly property bool available: d.available === true
    readonly property var timers: d.timers || []
    readonly property var presets: d.presets || []
    readonly property var cycle: d.pomodoro || ({})
    readonly property var pomodoro: T.first(timers, "pomodoro")
    readonly property var countdowns: timers.filter(function (t) { return t.kind === "countdown" })
    readonly property bool anyRunning: T.runningCount(timers) > 0

    // What the last refused action said (an i18n key), and the custom field's own complaint.
    property string errorKey: ""
    property string fieldError: ""

    Tick { id: clock; wanted: p.visible && p.anyRunning }

    function tr(key) { return I18n.tr(key) }
    function act(name, args, then) {
        Store.act(name, args, function (done, err) {
            p.errorKey = err ? (err.msg || "mod-timer.error.args") : ""
            if (then && !err) then()
        })
    }
    function start(args) {
        p.act("timer.start", args)
    }
    function custom() {
        var args = T.parseLength(field.text)
        if (args === null) {
            p.fieldError = "mod-timer.panel.custom.invalid"
            return
        }
        p.fieldError = ""
        p.act("timer.start", args, function () { field.text = "" })
    }
    function phaseName(phase) {
        if (phase === "short_break") return tr("mod-timer.phase.name.short")
        if (phase === "long_break") return tr("mod-timer.phase.name.long")
        return tr("mod-timer.phase.name.focus")
    }
    // Pauses a running timer, resumes a paused one; nothing for an ended one.
    function toggle(t) {
        if (t.state === "running") p.act("timer.pause", {id: t.id})
        else if (t.state === "paused") p.act("timer.resume", {id: t.id})
    }

    component Caption: Text {
        color: p.theme.dim
        font.pixelSize: p.theme.fsCaption
        font.family: p.theme.fam(text, p.theme.families)
    }

    Column {
        id: body
        width: p.width
        spacing: p.theme.gap

        Text {
            width: parent.width
            text: p.tr("mod-timer.panel.title")
            color: p.theme.fg
            font.pixelSize: p.theme.fsTitle
            font.weight: p.theme.wMedium
            font.family: p.theme.fam(text, p.theme.families)
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Text {
            visible: p.errorKey !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: p.tr(p.errorKey)
            color: p.theme.error
            font.pixelSize: p.theme.fsLabel
            font.family: p.theme.fam(text, p.theme.families)
            Accessible.role: Accessible.AlertMessage
            Accessible.name: text
        }

        Caption {
            visible: p.countdowns.length > 0
            text: p.tr("mod-timer.panel.running")
        }
        Repeater {
            model: p.countdowns
            delegate: Block {
                id: row
                required property var modelData
                readonly property var t: modelData
                readonly property bool ended: t.state === "ended"
                width: body.width
                height: rowBody.implicitHeight + 2 * p.theme.gap
                activeFocusOnTab: true
                Accessible.role: Accessible.ListItem
                Accessible.name: T.fill(p.tr("mod-timer.panel.a11y.timer"), {
                    label: T.nameOf(t, p.tr("mod-timer.name.timer")),
                    state: ended ? p.tr("mod-timer.panel.ended") : (t.state === "paused" ? p.tr("mod-timer.panel.paused") : ""),
                    time: ended ? "" : T.clock(T.left(t, clock.now))
                })
                Keys.onSpacePressed: p.toggle(row.t)

                Ring {
                    id: ringOf
                    x: p.theme.gap
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    height: 22
                    share: T.share(row.t, clock.now)
                    stroke: row.t.state === "paused" ? p.theme.dim : p.theme.accent
                    track: p.theme.outline
                }
                Row {
                    id: rowBody
                    x: ringOf.x + ringOf.width + p.theme.gap
                    y: p.theme.gap
                    width: row.width - x - p.theme.gap
                    spacing: p.theme.gap
                    Column {
                        width: rowBody.width - buttons.width - rowBody.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: T.nameOf(row.t, p.tr("mod-timer.name.timer"))
                            color: p.theme.fg
                            font.pixelSize: p.theme.fs
                            font.family: p.theme.fam(text, p.theme.families)
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: row.ended ? p.tr("mod-timer.panel.ended_at").replace("{time}", T.hhmm(row.t.ended_at_ms))
                                : row.t.state === "paused" ? T.clock(row.t.remaining_ms) + " · " + p.tr("mod-timer.panel.paused")
                                : p.tr("mod-timer.panel.left").replace("{time}", T.clock(T.left(row.t, clock.now)))
                            color: row.ended ? p.theme.accent : p.theme.dim
                            font.pixelSize: p.theme.fsLabel
                            font.features: ({"tnum": 1})
                            font.family: p.theme.fam(text, p.theme.families)
                        }
                    }
                    Row {
                        id: buttons
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: p.theme.xs
                        IconButton {
                            visible: !row.ended
                            icon: row.t.state === "paused" ? "play_arrow" : "pause"
                            a11y: row.t.state === "paused" ? p.tr("mod-timer.panel.resume") : p.tr("mod-timer.panel.pause")
                            onClicked: p.toggle(row.t)
                        }
                        Button {
                            label: p.tr("mod-timer.panel.add")
                            onClicked: p.act("timer.add", {id: row.t.id, minutes: 1})
                        }
                        IconButton {
                            icon: "stop"
                            a11y: p.tr("mod-timer.panel.stop")
                            onClicked: p.act("timer.stop", {id: row.t.id})
                        }
                    }
                }
            }
        }
        Caption {
            visible: p.countdowns.length === 0 && p.available
            width: parent.width
            wrapMode: Text.WordWrap
            text: p.tr("mod-timer.panel.empty")
        }

        Caption {
            text: p.tr("mod-timer.panel.presets")
        }
        Flow {
            width: parent.width
            spacing: p.theme.gap
            Repeater {
                model: p.presets
                delegate: Button {
                    required property var modelData
                    label: T.fill(p.tr("mod-timer.panel.preset"), {min: modelData})
                    onClicked: p.start({minutes: modelData})
                }
            }
        }

        Caption {
            text: p.tr("mod-timer.panel.custom")
        }
        Row {
            width: parent.width
            spacing: p.theme.gap
            Rectangle {
                id: field
                property alias text: input.text
                width: parent.width - startButton.width - p.theme.gap
                height: p.theme.controlH
                radius: p.theme.keycap ? p.theme.rFull : p.theme.rSm
                color: p.theme.surface
                border.width: input.activeFocus ? Math.max(1, p.theme.outlineW) : 1
                border.color: input.activeFocus ? p.theme.focusRing : p.theme.outline
                TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: p.theme.pad
                    anchors.rightMargin: p.theme.pad
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: p.theme.fg
                    selectionColor: p.theme.selected
                    selectedTextColor: p.theme.fgOnSelected
                    font.pixelSize: p.theme.fs
                    font.family: p.theme.fam(text, p.theme.families)
                    maximumLength: 8
                    Keys.onReturnPressed: p.custom()
                    Keys.onEnterPressed: p.custom()
                    Accessible.role: Accessible.EditableText
                    Accessible.name: p.tr("mod-timer.panel.custom")
                }
                Text {
                    visible: input.text === "" && !input.activeFocus
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: p.theme.pad
                    text: p.tr("mod-timer.panel.custom.placeholder")
                    color: p.theme.dim
                    font.pixelSize: p.theme.fs
                    font.family: p.theme.fam(text, p.theme.families)
                }
            }
            Button {
                id: startButton
                label: p.tr("mod-timer.panel.custom.start")
                onClicked: p.custom()
            }
        }
        Text {
            visible: p.fieldError !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: p.tr(p.fieldError)
            color: p.theme.error
            font.pixelSize: p.theme.fsLabel
            font.family: p.theme.fam(text, p.theme.families)
        }

        Block {
            id: pomo
            width: body.width
            height: pomoBody.implicitHeight + 2 * p.theme.gap
            Column {
                id: pomoBody
                x: p.theme.gap
                y: p.theme.gap
                width: pomo.width - 2 * p.theme.gap
                spacing: p.theme.gap
                Caption {
                    text: p.tr("mod-timer.panel.pomodoro")
                }
                Text {
                    visible: p.pomodoro === null
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: T.fill(p.tr("mod-timer.panel.pomodoro.idle"), {focus: p.cycle.focus_ms / 60000, rounds: p.cycle.rounds})
                    color: p.theme.dim
                    font.pixelSize: p.theme.fsLabel
                    font.family: p.theme.fam(text, p.theme.families)
                }
                Row {
                    visible: p.pomodoro !== null
                    spacing: p.theme.gap
                    Ring {
                        visible: p.pomodoro !== null && p.pomodoro.state !== "ended"
                        width: 48
                        height: 48
                        anchors.verticalCenter: parent.verticalCenter
                        share: T.share(p.pomodoro, clock.now)
                        stroke: p.pomodoro !== null && p.pomodoro.state === "paused" ? p.theme.dim
                            : p.pomodoro !== null && p.pomodoro.phase !== "focus" ? p.theme.tertiary : p.theme.accent
                        track: p.theme.outline
                        lineWidth: 4
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: p.pomodoro !== null ? p.phaseName(p.pomodoro.phase) + " · " + T.fill(p.tr("mod-timer.panel.round"), {n: p.pomodoro.round, rounds: p.pomodoro.rounds}) : ""
                            color: p.theme.fg
                            font.pixelSize: p.theme.fs
                            font.family: p.theme.fam(text, p.theme.families)
                        }
                        Text {
                            text: p.pomodoro === null ? ""
                                : p.pomodoro.state === "ended" ? p.tr("mod-timer.panel.ended")
                                : p.pomodoro.state === "paused" ? T.clock(p.pomodoro.remaining_ms) + " · " + p.tr("mod-timer.panel.paused")
                                : p.tr("mod-timer.panel.left").replace("{time}", T.clock(T.left(p.pomodoro, clock.now)))
                            color: p.pomodoro !== null && p.pomodoro.state === "ended" ? p.theme.accent : p.theme.dim
                            font.pixelSize: p.theme.fsLabel
                            font.features: ({"tnum": 1})
                            font.family: p.theme.fam(text, p.theme.families)
                        }
                    }
                }
                Flow {
                    width: parent.width
                    spacing: p.theme.gap
                    Button {
                        visible: p.pomodoro === null
                        label: p.tr("mod-timer.panel.pomodoro.start")
                        primary: true
                        onClicked: p.act("timer.pomodoro.start", {})
                    }
                    Button {
                        visible: p.pomodoro !== null && p.pomodoro.state !== "ended"
                        label: p.pomodoro !== null && p.pomodoro.state === "paused" ? p.tr("mod-timer.panel.resume") : p.tr("mod-timer.panel.pause")
                        onClicked: p.toggle(p.pomodoro)
                    }
                    Button {
                        visible: p.pomodoro !== null
                        label: p.tr("mod-timer.panel.skip")
                        onClicked: p.act("timer.skip", {id: p.pomodoro.id})
                    }
                    Button {
                        visible: p.pomodoro !== null
                        label: p.tr("mod-timer.panel.reset")
                        onClicked: p.act("timer.stop", {id: p.pomodoro.id})
                    }
                }
            }
        }
    }
}
