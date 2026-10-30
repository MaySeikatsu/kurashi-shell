import QtQuick
import "../../../core"
import "../.."
import ".."

// Classic (W53.1): the bevel-era start button — a raised push button `thickness − 6` px tall (22 in a 28 px taskbar, as 98's),
// the mark 2 px inside the bevel, the bold label 3 px after it; held pressed (sunk, the content 1 px down-right, a dotted
// focus rectangle inside) while the launcher is open. The mark is original: a four-pane window in the palette's caption
// and desk roles with a 1 px shadow — never a vendor's logo. Drawn from tokens only (rule 4); static (0 frames idle).
// Two callers, one part: StartHost sets label/pressed/open/vertical; the bar's `launcher` module (W53.0b, contract row 561)
// also sets `thickness` and listens to `clicked`.
StartBase {
    id: st
    property real thickness: Theme.barH
    signal clicked()

    readonly property bool down: pressed || open || hit.pressed
    readonly property int shift: down ? 1 : 0
    readonly property bool showLabel: label !== "" && !vertical
    implicitHeight: Math.max(16, Math.round(thickness) - 6)
    implicitWidth: vertical ? implicitHeight : 4 + 16 + (showLabel ? 3 + Math.ceil(text.implicitWidth) + 1 : 0) + 4
    width: implicitWidth
    height: implicitHeight

    Accessible.role: Accessible.Button
    Accessible.name: label !== "" ? label : I18n.tr("layout.module.launcher")
    Accessible.onPressAction: st.clicked()

    Rectangle { anchors.fill: parent; color: Theme.surface }
    BevelEdge {
        anchors.fill: parent
        w: Theme.crisp(1, Screen.devicePixelRatio)
        sunk: st.down
    }
    // While held open: 98's dotted rectangle 3 px inside the edge.
    FocusRing {
        anchors.fill: parent
        shown: st.open
        stroke: Theme.fg
    }

    // The mark: a 16 × 16 cell, a 13 × 13 window of four panes with black mullions and a shadow 1 px down-right.
    Item {
        id: mark
        x: (st.vertical ? Math.floor((st.width - 16) / 2) : 4) + st.shift
        y: Math.floor((st.height - 16) / 2) + st.shift
        width: 16
        height: 16
        readonly property color edge: Theme.fg
        Rectangle { x: 2; y: 15; width: 13; height: 1; color: Theme.bevelDark2 }
        Rectangle { x: 14; y: 3; width: 1; height: 13; color: Theme.bevelDark2 }
        Rectangle { x: 1; y: 2; width: 13; height: 13; color: mark.edge }
        Rectangle { x: 2; y: 3; width: 5; height: 5; color: Theme.color("color.title", "#000080") }
        Rectangle { x: 8; y: 3; width: 5; height: 5; color: Theme.color("color.title_end", "#1084d0") }
        Rectangle { x: 2; y: 9; width: 5; height: 5; color: Theme.color("color.desk", "#008080") }
        Rectangle { x: 8; y: 9; width: 5; height: 5; color: Theme.color("color.info", "#ffffe1") }
        // A highlight on the panes' top-left, as 9x icons lit their glass.
        Rectangle { x: 2; y: 3; width: 2; height: 1; color: Qt.lighter(Theme.color("color.title", "#000080"), 2.2) }
        Rectangle { x: 8; y: 3; width: 2; height: 1; color: Qt.lighter(Theme.color("color.title_end", "#1084d0"), 1.4) }
    }
    PixelLabel {
        id: text
        visible: st.showLabel
        x: 4 + 16 + 3 + st.shift
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: st.shift
        text: st.label
        weight: Theme.wBold
    }
    MouseArea {
        id: hit
        anchors.fill: parent
        onClicked: st.clicked()
    }
}
