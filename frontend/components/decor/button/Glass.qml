import QtQuick
import "../../../core"

// Glass (W53.2): a glass-era push button — Windows 7's (docs/ux/styles.md §3; 7.css `_variables.scss`, checked on
// Microsoft's UX guide capture learn.microsoft.com/…/uxguide/images/ctrl-balloons-image2.png, the OK button): 3 px
// corners, a 1 px grey rim (`outline`) with a light inner rim, the face split at half height — a pale grey above, a
// deeper grey below; hovered, the accent's pale blue in the same split and a blue rim; pressed, deeper blue; the default
// button with the accent's blue rim at rest. The caller's content sits on it. Static (one paint per state).
ButtonBase {
    id: bf
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property bool blue: hovered || pressed || checked
    readonly property color base: Theme.color("color.surface_container_low", "#f2f2f2")
    readonly property color tint: Qt.tint(base, Qt.alpha(Theme.accent, pressed || checked ? 0.32 : 0.18))
    readonly property color hi: blue ? Qt.lighter(tint, 1.05) : base
    readonly property color lo: blue ? Qt.darker(tint, 1.12) : Qt.darker(base, 1.1)
    Rectangle {
        anchors.fill: parent
        radius: 3
        color: bf.blue || bf.primary ? Qt.darker(Theme.accent, 1.15) : Theme.color("color.outline", "#707070")
    }
    Rectangle {
        anchors { fill: parent; margins: bf.hair }
        radius: 2
        border.width: bf.hair
        border.color: Qt.rgba(1, 1, 1, bf.pressed ? 0.3 : 0.8)
        gradient: Gradient {
            GradientStop { position: 0; color: bf.hi }
            GradientStop { position: 0.45; color: Qt.darker(bf.hi, 1.03) }
            GradientStop { position: 0.46; color: bf.lo }
            GradientStop { position: 1; color: Qt.darker(bf.lo, 1.08) }
        }
    }
}
