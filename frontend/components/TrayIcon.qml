import QtQuick
import Quickshell
import "../core"

// One StatusNotifierItem in the bar. Square and as tall as the bar, so the pointer target is the
// bar's full thickness. The picture comes from the first source that loads: the item's own pixmap,
// its icon theme path, the desktop's icon for its name, else the first letter of its title. A
// NeedsAttention item gets an accent dot (colour, not motion). Presentational: it reports clicks and
// wheel steps; the Bar turns them into tray.* actions.
Item {
    id: ti
    property string title: ""
    property string iconName: ""
    property string iconTheme: ""     // icon_theme_path: the directories the item ships its icons in
    property string pixmap: ""        // data:image/png;base64,… from icon_pixmap, or ""
    property bool attention: false    // status NeedsAttention
    property bool hasMenu: false      // a right click can open the item's menu
    property bool menuOnly: false     // ItemIsMenu: the item only offers its menu, so left click opens it
    property string tip: ""           // tooltip; the accessible description (no hover popup, see Bar)
    // The hover peek (K35, B9): the Stage draws the item's title and tooltip on the output named here. "" offers none.
    property string peekSource: ""    // "tray:<item id>"
    property string peekOutput: ""
    // K61 (docs/ux/texture.md "Controls"): the picture and the disc sit on a transparent square at rest, where a relief
    // would halo over the bar's own relief; so the relief comes with the hover square (opaque, over the picture and the
    // disc) and the disc carries its own while the square is not hovered. Only in a window that shares its sheet.
    readonly property var qsw: Window.window ? QsWindow.window : null
    readonly property bool shared: !!(qsw && qsw.tileSheet)
    readonly property bool squareRelief: Theme.texControls && shared && hover.hovered
    readonly property bool discRelief: Theme.texControls && shared && !hover.hovered && img.status !== Image.Ready

    // action: "activate" (left), "secondary" (middle), "menu" (right, only with a menu); x and y are
    // in this item's coordinates.
    signal requested(string action, real x, real y)
    // One wheel notch as an SNI scroll step (orientation "vertical" or "horizontal").
    signal scrolled(int delta, string orientation)

    width: Theme.barH
    height: Theme.barH
    Accessible.role: Accessible.Button
    Accessible.name: ti.title
    Accessible.description: ti.tip

    // Candidate pictures, in order; a candidate that fails to load is skipped (see `idx`).
    readonly property var cands: [
        ti.pixmap,
        (ti.iconTheme !== "" && ti.iconName !== "") ? "file://" + ti.iconTheme + "/" + ti.iconName + ".png" : "",
        (ti.iconName !== "" && Quickshell.hasThemeIcon(ti.iconName)) ? Quickshell.iconPath(ti.iconName) : ""
    ].filter(function (s) { return s !== "" })
    property int idx: 0
    onCandsChanged: idx = 0

    HoverHandler { id: hover }
    PeekSource { target: ti; source: ti.peekSource; output: ti.peekOutput; hovered: hover.hovered }
    Rectangle {
        anchors.centerIn: parent
        width: parent.width - 6
        height: parent.height - 6
        radius: Theme.rSm
        color: hover.hovered ? Theme.containerHigh : "transparent"
    }

    Image {
        id: img
        anchors.centerIn: parent
        width: 20
        height: 20
        // Decoded at display size: a tray icon never needs its source resolution in memory.
        sourceSize: Qt.size(40, 40)
        fillMode: Image.PreserveAspectFit
        smooth: true
        source: ti.idx < ti.cands.length ? ti.cands[ti.idx] : ""
        onStatusChanged: if (status === Image.Error) ti.idx++
    }

    // The fallback glyph: shown until the picture is ready, and for good when none loads.
    Rectangle {
        id: disc
        anchors.centerIn: parent
        width: 20
        height: 20
        radius: 10
        color: Theme.containerHigh
        visible: img.status !== Image.Ready
        Loader {
            active: ti.discRelief
            anchors.fill: parent
            sourceComponent: Relief { anchors.fill: parent; radius: 10 }
        }
    }
    // The relief over a hovered square: its picture and its disc, once (the disc carries none then).
    Loader {
        active: ti.squareRelief
        anchors.centerIn: parent
        width: parent.width - 6
        height: parent.height - 6
        sourceComponent: Relief { anchors.fill: parent; radius: Theme.rSm }
    }
    // The letter of the disc sits above the relief, as a label does.
    Text {
        anchors.centerIn: parent
        visible: disc.visible
        color: Theme.fg
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: ti.title !== "" ? ti.title.charAt(0) : "•"
    }

    Rectangle {
        visible: ti.attention
        width: 8
        height: 8
        radius: 4
        color: Theme.accent
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 5
        anchors.topMargin: 5
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) ti.requested(ti.menuOnly && ti.hasMenu ? "menu" : "activate", mouse.x, mouse.y)
            else if (mouse.button === Qt.MiddleButton) ti.requested("secondary", mouse.x, mouse.y)
            else if (mouse.button === Qt.RightButton && ti.hasMenu) ti.requested("menu", mouse.x, mouse.y)
        }
        // Touchpads send many small deltas: one step per 120 units, in the direction of travel.
        property real acc: 0
        onWheel: w => {
            var vertical = w.angleDelta.y !== 0
            var d = vertical ? w.angleDelta.y : w.angleDelta.x
            if (d === 0) return
            acc += d
            while (Math.abs(acc) >= 120) {
                var up = acc > 0
                acc -= up ? 120 : -120
                // SNI scroll: positive is down or right (the GDK convention most hosts pass on).
                ti.scrolled(up ? -1 : 1, vertical ? "vertical" : "horizontal")
            }
        }
    }
}
