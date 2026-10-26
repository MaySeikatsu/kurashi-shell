import QtQuick
import "Timer.js" as T

// The island's compact face of the timer (K73, docs/ux/timer.md "Island face"): a ring and the time left of the first running
// countdown. While the end's face is up (the daemon raises it for a few seconds after an end, then lowers it), the face says
// "Time is up" in the accent colour for the timer that ended, whatever else runs. Its expanded view is the panel
// (FaceExpanded.qml). It reads the document only while it shows (Ma), and it ticks only while it shows, which is only while a
// countdown runs or an end's face is up: the end's window is closed on time by that tick.
Item {
    // Handed in by ModLoader (K26 loader contract; K24 faces get the same props).
    required property var store
    required property var theme
    required property var i18n
    id: face

    Component.onCompleted: face.store.watch("mod.timer")
    Component.onDestruction: face.store.unwatch("mod.timer")

    readonly property var d: face.store.docs["mod.timer"] || ({})
    Tick { id: clock; wanted: face.visible }

    // The end the face speaks for: a timer that ended within the window before the clock's now.
    readonly property var ended: T.justEnded(d.timers, clock.now)
    readonly property bool isEnd: ended !== null && ended !== undefined
    // The countdown the face counts down: the first running timer.
    readonly property var live: T.firstRunning(d.timers)
    readonly property bool counting: !isEnd && live !== null && live !== undefined

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: face.theme.gap
        anchors.verticalCenter: parent.verticalCenter
        Ring {
            visible: face.counting
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            share: T.share(face.live, clock.now)
            stroke: face.theme.accent
            track: face.theme.outline
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== ""
            text: face.isEnd ? face.i18n.tr("mod-timer.face.ended")
                : face.counting ? T.clock(T.left(face.live, clock.now)) : ""
            color: face.isEnd ? face.theme.accent : face.theme.fg
            font.pixelSize: face.theme.fsLabel
            font.features: ({"tnum": 1})
            font.family: face.theme.fam(text, face.theme.families)
            Accessible.role: Accessible.StaticText
            Accessible.name: face.isEnd ? face.i18n.tr("mod-timer.face.ended")
                : face.counting ? T.fill(face.i18n.tr("mod-timer.face.a11y"), {
                    label: T.nameOf(face.live, face.i18n.tr("mod-timer.name.timer")),
                    time: T.clock(T.left(face.live, clock.now))
                }) : ""
        }
    }
}
