import QtQuick
import "Timer.js" as T

// The island's compact face of the timer (K73, docs/ux/timer.md "Island face"): a ring and the time left of the nearest
// countdown while one runs, and "Time is up" in the accent colour when the end's face is up (the daemon raises it for the
// end's transient, and clears it). Its expanded view is the panel (FaceExpanded.qml). It reads the document only while it
// shows (Ma), and its second clock runs only while a countdown runs.
Item {
    // Handed in by ModLoader (K26 loader contract; K24 faces get the same props).
    required property var store
    required property var theme
    required property var i18n
    id: face

    Component.onCompleted: face.store.watch("mod.timer")
    Component.onDestruction: face.store.unwatch("mod.timer")

    readonly property var d: face.store.docs["mod.timer"] || ({})
    readonly property var nearest: T.nearest(d.timers)
    readonly property bool showing: nearest !== null && nearest !== undefined
    readonly property bool running: showing && nearest.state === "running"
    readonly property bool ended: showing && nearest.state === "ended"

    Tick { id: clock; wanted: face.visible && face.running }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: face.theme.gap
        anchors.verticalCenter: parent.verticalCenter
        Ring {
            visible: face.running || (face.showing && face.nearest.state === "paused")
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            share: T.share(face.nearest, clock.now)
            stroke: face.theme.fg
            track: face.theme.outline
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== ""
            text: face.ended ? face.i18n.tr("mod-timer.face.ended")
                : face.showing ? T.clock(T.left(face.nearest, clock.now)) : ""
            color: face.ended ? face.theme.accent : face.theme.fg
            font.pixelSize: face.theme.fsLabel
            font.features: ({"tnum": 1})
            font.family: face.theme.fam(text, face.theme.families)
            Accessible.role: Accessible.StaticText
            Accessible.name: face.ended ? face.i18n.tr("mod-timer.face.ended")
                : face.showing ? T.fill(face.i18n.tr("mod-timer.face.a11y"), {
                    label: T.nameOf(face.nearest, face.i18n.tr("mod-timer.name.timer")),
                    time: T.clock(T.left(face.nearest, clock.now))
                }) : ""
        }
    }
}
