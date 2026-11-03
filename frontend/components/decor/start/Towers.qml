import QtQuick
import "../../../core"
import "../.."
import ".."

// Towers (session 20, I374): the PS2 look's start mark — four light towers of uneven height on a thin floor line,
// in red, yellow, teal and blue, after the boot screen's towers of light. Our original mark: never Sony's logo, its
// letters or the controller's symbols. The colours are the mark's own (a console's four, like the look's glow), dimmed
// a little at rest and full while the launcher is open or pressed. Static (0 frames idle).
StartBase {
    id: st
    property real thickness: Theme.barH
    signal clicked()
    readonly property bool lit: open || pressed || hit.pressed
    readonly property real h: Math.max(16, Math.round(thickness))
    readonly property var colours: ["#e03a3e", "#f2c230", "#1fa59a", "#3d7ec2"]
    implicitHeight: h
    implicitWidth: vertical ? h : Math.round(Math.max(28, h * 1.2))
    width: implicitWidth
    height: implicitHeight

    Accessible.role: Accessible.Button
    Accessible.name: I18n.tr("layout.module.launcher")
    Accessible.onPressAction: st.clicked()

    // The hover and held-open highlight: a faint disc of the text's ink, as the plain icon button's.
    Rectangle {
        anchors.centerIn: parent
        width: Math.round(st.h * 0.9)
        height: width
        radius: width / 2
        visible: st.lit || hit.containsMouse
        color: Qt.alpha(Theme.fg, st.lit ? 0.16 : 0.08)
    }
    Item {
        id: mark
        readonly property int s: Math.round(Math.min(st.h * 0.62, 18))
        readonly property int bar: Math.max(2, Math.round(s / 6))
        readonly property int gap: Math.max(1, Math.round(bar / 2))
        width: 4 * bar + 3 * gap
        height: s
        anchors.centerIn: parent
        opacity: st.lit || hit.containsMouse ? 1 : 0.85
        Repeater {
            model: 4
            Rectangle {
                required property int index
                width: mark.bar
                // Uneven, tallest second (as the boot screen's towers stand), so they never read as signal bars.
                height: Math.round(mark.s * [0.62, 1.0, 0.8, 0.5][index]) - mark.bar
                x: index * (mark.bar + mark.gap)
                y: mark.height - mark.bar - height
                radius: Math.min(1, width / 2)
                color: st.colours[index]
            }
        }
        // The floor the towers stand on: one line in the text's ink.
        Rectangle {
            width: parent.width
            height: Math.max(1, Math.round(mark.bar / 2))
            y: parent.height - height
            color: Qt.alpha(Theme.fg, 0.7)
        }
    }
    FocusRing {
        anchors.fill: parent
        anchors.margins: 2
        shown: st.activeFocus
    }
    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        onClicked: st.clicked()
    }
}
