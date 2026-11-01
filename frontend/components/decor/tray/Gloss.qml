import QtQuick
import "../../../core"

// Gloss (W53.2): a glossy tray well — Windows XP's notification area (docs/ux/styles.md §2, measured from
// guidebookgallery.org's pics/gui/desktop/full/winxppro.png, x 707–799): a lighter blue than the taskbar
// (`[decor] tray.fill`), set off at its start by one dark and one light px, its top two px bright, a darker line at top
// and bottom. Vertical bars (a side taskbar) turn it: the lines run along the top. Static; colours from roles (rule 4).
TrayBase {
    id: tw
    readonly property string role: Theme.decor("tray.fill", "")
    readonly property color c: role !== "" ? role : Qt.lighter(Theme.accent, 1.25)
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property real t: Math.max(1, height)

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.darker(tw.c, 1.5) }
            GradientStop { position: 1 / tw.t; color: Qt.lighter(tw.c, 1.18) }
            GradientStop { position: 2.5 / tw.t; color: Qt.lighter(tw.c, 1.24) }
            GradientStop { position: 5 / tw.t; color: tw.c }
            GradientStop { position: 0.5; color: Qt.darker(tw.c, 1.04) }
            GradientStop { position: 0.82; color: Qt.lighter(tw.c, 1.06) }
            GradientStop { position: 1 - 2 / tw.t; color: Qt.darker(tw.c, 1.08) }
            GradientStop { position: 1; color: Qt.darker(tw.c, 1.5) }
        }
    }
    // The start edge: dark, then light (on a side bar, the top edge).
    Rectangle {
        color: Qt.darker(tw.c, 2.6)
        width: tw.vertical ? tw.width : tw.hair
        height: tw.vertical ? tw.hair : tw.height
    }
    Rectangle {
        color: Qt.lighter(tw.c, 1.3)
        x: tw.vertical ? 0 : tw.hair
        y: tw.vertical ? tw.hair : 0
        width: tw.vertical ? tw.width : tw.hair
        height: tw.vertical ? tw.hair : tw.height
    }
}
