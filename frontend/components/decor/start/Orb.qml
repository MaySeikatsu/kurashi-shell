import QtQuick
import QtQuick.Effects
import "../../../core"
import "../.."
import ".."

// Orb (W53.2): the round glass start button — Windows 7's orb (docs/ux/styles.md §3, measured from Microsoft's Windows 7
// UX guide capture learn.microsoft.com/…/uxguide/images/winenv-taskbar-image1.png: a 39 px disc centred in a ~58 px
// start area of the 40 px superbar; 7's orb sits inside the bar, Vista's overhung it). A dark glass sphere in
// `[decor] start.fill` (its role darkened at the rim), a white elliptic highlight over its upper half, a light glow
// rising from its foot, and the original four-pane mark (PaneMark, glowing; never a vendor's logo) in its middle. Hover
// lights a halo round it; pressed or while the launcher is open it deepens. No label (7 showed none; `start.label` is
// read only for the accessible name). Drawn from tokens only (rule 4); static (0 frames idle).
StartBase {
    id: st
    property real thickness: Theme.barH
    // The start-menu skin the launcher draws while this dress is the look's (contract start/StartMenuBase.qml, row 563).
    menu: Qt.resolvedUrl("GlassMenu.qml")
    signal clicked()

    readonly property var fills: Theme.decor("start.fill", [])
    readonly property color c: fills.length > 0 ? fills[0] : Theme.accent
    readonly property bool down: pressed || open || hit.pressed
    readonly property bool hot: hit.containsMouse
    readonly property real h: Math.max(16, Math.round(thickness))
    readonly property real d: Math.max(14, Math.min(h, 48) - 1)
    implicitHeight: h
    implicitWidth: vertical ? h : Math.round(h * 1.45)
    width: implicitWidth
    height: implicitHeight

    Accessible.role: Accessible.Button
    Accessible.name: label !== "" ? label : I18n.tr("layout.module.launcher")
    Accessible.onPressAction: st.clicked()

    // The halo while hovered or open.
    RectangularShadow {
        anchors.centerIn: orb
        width: orb.width; height: orb.height
        radius: width / 2
        blur: st.d * 0.35
        spread: 0
        visible: st.hot || st.down
        color: Qt.alpha(Qt.lighter(st.c, 2.2), st.down ? 0.55 : 0.8)
    }
    Item {
        id: orb
        width: st.d
        height: st.d
        anchors.centerIn: parent
        // The sphere: a dark glass body, deepest under the middle, a light foot.
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            border.width: 1
            border.color: Qt.darker(st.c, 3.2)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.darker(st.c, st.down ? 1.9 : 1.5) }
                GradientStop { position: 0.45; color: Qt.darker(st.c, st.down ? 2.6 : 2.1) }
                GradientStop { position: 0.72; color: Qt.darker(st.c, st.down ? 1.9 : 1.45) }
                GradientStop { position: 1; color: Qt.lighter(st.c, st.hot ? 2.1 : 1.7) }
            }
        }
        // The foot's glow, an ellipse fading upward.
        Rectangle {
            x: parent.width * 0.16; y: parent.height * 0.6
            width: parent.width * 0.68; height: parent.height * 0.38
            radius: height / 2
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(Qt.lighter(st.c, 2.4), 0) }
                GradientStop { position: 1; color: Qt.alpha(Qt.lighter(st.c, 2.4), st.hot ? 0.75 : 0.55) }
            }
        }
        PaneMark {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 1
            size: Math.round(st.d * 0.5)
            lift: 0.15
            glow: st.hot ? 0.9 : 0.55
            slant: 0.1
        }
        // The glass highlight over the upper half.
        Rectangle {
            x: parent.width * 0.12; y: parent.height * 0.05
            width: parent.width * 0.76; height: parent.height * 0.46
            radius: height / 2
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, st.down ? 0.45 : 0.7) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.06) }
            }
        }
    }
    FocusRing {
        anchors.fill: orb
        anchors.margins: -2
        shown: st.activeFocus
    }
    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        onClicked: st.clicked()
    }
}
