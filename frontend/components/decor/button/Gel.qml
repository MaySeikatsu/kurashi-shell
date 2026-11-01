import QtQuick
import "../../../core"

// Gel (W53.4): Aqua's push button — Mac OS X 10.2–10.4 (docs/ux/styles.md §5): a capsule (`[decor] button.radius`, -1 =
// half the height) in a 1 px rim, its face a gel lit from above — a light upper half with a white highlight, a deeper
// band at the middle and the colour glowing up again at its foot (`button.gloss` scales the light; 0 = flat). A plain
// button is clear gel over the window's grey, the default (`primary`) Aqua blue in the accent; pressed darkens the gel.
// The default button pulses (`button.pulse` times, each `button.pulse_ms` long: the glow rises and falls) once it is
// shown — and then rests: one SequentialAnimation with a loop count, restarted only when the button turns default or
// visible again, never under motion `none` (reduce motion). 0 frames idle once it rests (Ma). Text stays black (10.x's
// labels on gel were black), `ink`.
ButtonBase {
    id: gb
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property real g: Theme.decor("button.gloss", 0.9)
    readonly property real r: Theme.decor("button.radius", -1) >= 0 ? Math.min(Theme.decor("button.radius", -1), height / 2) : height / 2
    readonly property color base: primary ? Qt.lighter(Theme.accent, 1.3) : Theme.color("color.surface_container_lowest", "#ffffff")
    readonly property color rim: primary ? Qt.darker(Theme.accent, 1.55) : Qt.darker(Theme.outline, 1.05)
    readonly property bool down: pressed || checked
    readonly property int pulses: Theme.decor("button.pulse", 0)
    readonly property int pulseMs: Theme.decor("button.pulse_ms", 1500)
    readonly property bool canPulse: primary && pulses > 0 && visible && Theme.motionKind !== "none"
    ink: Theme.color("color.on_surface", "#000000")

    // The glow the pulse lifts (0 at rest).
    property real glow: 0
    onCanPulseChanged: if (canPulse) pulse.restart(); else { pulse.stop(); glow = 0 }
    Component.onCompleted: if (canPulse) pulse.restart()
    SequentialAnimation {
        id: pulse
        loops: Math.max(1, gb.pulses)
        NumberAnimation { target: gb; property: "glow"; from: 0; to: 1; duration: gb.pulseMs / 2; easing.type: Easing.InOutSine }
        NumberAnimation { target: gb; property: "glow"; from: 1; to: 0; duration: gb.pulseMs / 2; easing.type: Easing.InOutSine }
    }

    Rectangle {
        anchors.fill: parent
        radius: gb.r
        color: gb.rim
    }
    Rectangle {
        id: face
        anchors { fill: parent; margins: gb.hair }
        radius: Math.max(0, gb.r - gb.hair)
        readonly property color c: gb.down ? Qt.darker(gb.base, gb.primary ? 1.25 : 1.18) : gb.base
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.tint(face.c, Qt.rgba(1, 1, 1, 0.55 * gb.g)) }
            GradientStop { position: 0.48; color: Qt.tint(face.c, Qt.rgba(1, 1, 1, 0.18 * gb.g)) }
            GradientStop { position: 0.52; color: Qt.darker(face.c, 1 + (gb.primary ? 0.1 : 0.08) * gb.g) }
            GradientStop { position: 1; color: Qt.tint(face.c, Qt.rgba(1, 1, 1, 0.45 * gb.g)) }
        }
    }
    // The pulse: the default button brightens and falls back.
    Rectangle {
        anchors { fill: parent; margins: gb.hair }
        radius: face.radius
        visible: gb.glow > 0
        color: Qt.rgba(1, 1, 1, 0.32 * gb.glow)
    }
    // The highlight on the upper half.
    Rectangle {
        visible: gb.g > 0 && !gb.down
        x: gb.r * 0.6; y: Math.max(1, gb.height * 0.06)
        width: gb.width - 2 * x; height: gb.height * 0.4
        radius: height / 2
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.85 * gb.g) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.1 * gb.g) }
        }
    }
}
