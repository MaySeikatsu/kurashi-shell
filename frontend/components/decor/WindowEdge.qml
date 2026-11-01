import QtQuick
import "../../core"

// WindowEdge (W53.2): a captioned card's window frame under a look without the bevel chrome — `[decor] border.width` px in
// `border.color`, rounded `radius` — as XP's 3 px Luna frame (lit lines on the left and top, deeper ones on the right
// and bottom; measured on guidebookgallery.org's winxppro desktop, x 124–126 and 532–534) and 7's 8 px glass (a dark
// outer line, a light rim, the glass — translucent with the theme's surface alpha — and a dark line against the content;
// commons.wikimedia.org "SeaMonkey 2.46 on Windows 7.png", x 14–21). Bevel looks keep BevelEdge (row 595). Colours from
// roles (rule 4); static.
Item {
    id: we
    property real radius: 0
    readonly property int w: Math.max(1, Math.round(Theme.decor("border.width", 1)))
    readonly property string role: Theme.decor("border.color", "")
    readonly property color c: role !== "" ? role : Theme.outline
    readonly property real a: Theme.tok("color.surface_alpha", 1)
    readonly property bool glassy: a < 0.999
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)

    // The band: one ring of `w` px (a rounded outline that wide), translucent on a glass look.
    Rectangle {
        anchors.fill: parent
        radius: we.radius
        color: "transparent"
        border.width: we.w
        border.color: we.glassy ? Qt.alpha(we.c, 0.62 * we.a) : we.c
    }
    // Lit from the top left: a lighter line one px inside the outer edge, on the top and left.
    Rectangle {
        anchors { fill: parent; margins: we.hair }
        radius: Math.max(0, we.radius - 1)
        color: "transparent"
        border.width: we.hair
        border.color: we.glassy ? Qt.rgba(1, 1, 1, 0.5) : Qt.lighter(we.c, 1.15)
    }
    // The outer line, darker; and on an opaque look the right and bottom deeper still.
    Rectangle {
        anchors.fill: parent
        radius: we.radius
        color: "transparent"
        border.width: we.hair
        border.color: we.glassy ? Qt.rgba(0, 0, 0, 0.6) : Qt.darker(we.c, 1.12)
    }
    Rectangle {
        visible: !we.glassy && we.w > 1
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right; topMargin: we.radius; bottomMargin: we.radius }
        width: Math.min(2, we.w)
        color: Qt.darker(we.c, 1.8)
    }
    Rectangle {
        visible: !we.glassy && we.w > 1
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: we.radius; rightMargin: we.radius }
        height: Math.min(2, we.w)
        color: Qt.darker(we.c, 1.8)
    }
    // The dark line where the frame meets the content.
    Rectangle {
        anchors { fill: parent; margins: we.w }
        radius: Math.max(0, we.radius - we.w)
        color: "transparent"
        border.width: we.hair
        border.color: we.glassy ? Qt.rgba(0.2, 0.25, 0.32, 0.7) : Qt.darker(we.c, 1.05)
    }
}
