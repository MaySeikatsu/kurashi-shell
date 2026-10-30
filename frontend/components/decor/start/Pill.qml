import QtQuick
import "../../../core"
import "../.."
import ".."

// Pill (W53.2): the glossy start button — Windows XP's green "start" (docs/ux/styles.md §2, measured from
// guidebookgallery.org's pics/gui/desktop/full/winxppro.png, x 0–95 of the 30 px taskbar): the bar's full thickness, the
// screen-side end square and the other rounded, a vertical gloss in `[decor] start.fill` (a dark first px, a lighter
// band at the top, the body, a darker foot), a dark rim along the rounded end; the original four-pane mark (PaneMark,
// never a vendor's logo) and, with `start.label`, the label in lower case, bold, in `font.start` (`start.family`:
// Franklin Gothic → Libre Franklin) at `start.size`, italic with `start.italic`, a 1 px shadow under it. Hover lightens
// it; pressed or while the launcher is open it darkens. On a side bar only the mark, in a square. Drawn from tokens only
// (rule 4); static (0 frames idle). Contract: StartBase + the `launcher` module's `thickness`/`clicked` (row 561).
StartBase {
    id: st
    property real thickness: Theme.barH
    signal clicked()

    readonly property var fills: Theme.decor("start.fill", [])
    readonly property color c: fills.length > 0 ? fills[0] : Theme.secondary
    readonly property bool down: pressed || open || hit.pressed
    readonly property bool hot: hit.containsMouse && !down
    readonly property bool showLabel: label !== "" && !vertical
    readonly property real h: Math.max(16, Math.round(thickness))
    readonly property real r: Math.round(h * 0.42)
    readonly property real markSize: Math.round(h * 0.72)
    implicitHeight: h
    implicitWidth: vertical ? h : Math.round(h * 0.2) + markSize + (showLabel ? Math.round(h * 0.2) + Math.ceil(word.implicitWidth) : 0) + r + 4
    width: implicitWidth
    height: implicitHeight

    Accessible.role: Accessible.Button
    Accessible.name: label !== "" ? label : I18n.tr("layout.module.launcher")
    Accessible.onPressAction: st.clicked()

    readonly property color base: down ? Qt.darker(c, 1.18) : hot ? Qt.lighter(c, 1.08) : c
    function at(px) { return Math.max(0, Math.min(1, px / h)) }

    Rectangle {
        anchors.fill: parent
        topRightRadius: st.vertical ? st.r : st.r
        bottomRightRadius: st.r
        topLeftRadius: st.vertical ? st.r : 0
        bottomLeftRadius: st.vertical ? st.r : 0
        border.width: 1
        border.color: Qt.alpha(Qt.darker(st.c, 1.9), 0.85)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.darker(st.base, 1.2) }
            GradientStop { position: st.at(1); color: Qt.tint(st.base, Qt.rgba(1, 1, 1, st.down ? 0.08 : 0.2)) }
            GradientStop { position: st.at(3); color: Qt.tint(st.base, Qt.rgba(1, 1, 1, st.down ? 0.12 : 0.38)) }
            GradientStop { position: st.at(5); color: Qt.tint(st.base, Qt.rgba(1, 1, 1, st.down ? 0.06 : 0.18)) }
            GradientStop { position: st.at(st.h * 0.32); color: st.base }
            GradientStop { position: st.at(st.h * 0.8); color: Qt.darker(st.base, 1.18) }
            GradientStop { position: st.at(st.h - 1.5); color: Qt.darker(st.base, 1.45) }
            GradientStop { position: 1; color: Qt.darker(st.base, 1.6) }
        }
    }
    PaneMark {
        id: mark
        size: st.markSize
        x: st.vertical ? Math.round((st.width - size) / 2) : Math.round(st.h * 0.2)
        y: Math.round((st.height - size) / 2) + (st.down ? 1 : 0)
    }
    Item {
        visible: st.showLabel
        x: mark.x + mark.width + Math.round(st.h * 0.2)
        y: (st.down ? 1 : 0)
        height: st.height
        width: word.implicitWidth
        readonly property string fam: Theme.tok("font.start", "") || Theme.fam(st.label, Theme.families)
        Text {
            x: 1
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            text: word.text
            font: word.font
            color: Qt.alpha(Qt.darker(st.c, 2.6), 0.85)
        }
        Text {
            id: word
            anchors.verticalCenter: parent.verticalCenter
            text: st.label.toLocaleLowerCase()
            color: Qt.rgba(1, 1, 1, 1)
            font.family: parent.fam
            font.pixelSize: Theme.decor("start.size", 0) > 0 ? Theme.decor("start.size", 0) : Math.round(st.h * 0.6)
            font.weight: Font.Bold
            font.italic: Theme.decor("start.italic", false) === true
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
