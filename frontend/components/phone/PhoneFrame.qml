import QtQuick

// A phone seen from the front (W21, K42; docs/ux/quick-settings.md and docs/ux/webdock.md "Session 9 phone"): the body
// with its bezel, a rounded screen, a pill cut-out at the top of the screen (dynamic-island style), a status row beside
// the cut-out, side buttons (a volume rocker on the left, power on the right) and a home indicator at the bottom. The
// content goes on the screen between the status row and the home indicator (`area`). Drawn from tokens only (rule 4):
//   keycap chrome  an outline in `line`, a rim in `ring`, a dark glass bezel in `line`, the hard shadow straight down;
//   flat chrome    a thin dark bezel in `line` with a hairline in `outline`; no rim, no shadow.
// It imports nothing but QtQuick, so the web host (mods/webdock/host, which cannot import the shell's components) uses
// this very file through a link; the caller hands it its Theme singleton (`theme`). Width includes the side buttons
// (they stand `stick` px out of the body) and height the shadow. Static: no animation, no timer (Ma).
Item {
    id: ph

    property var theme: null
    // The content's own height: the frame's implicit height is the chrome around it plus this.
    property real contentHeight: 0
    property bool buttons: true
    property bool homeBar: true
    // The screen's ground (the web card hands it the skeleton's colour).
    property color screenColor: theme ? theme.container : "#252329"
    // The status row's two sides, beside the cut-out: the caller's items (a time, glyphs).
    property alias statusLeft: leftSlot.data
    property alias statusRight: rightSlot.data
    default property alias content: area.data
    readonly property alias area: area
    readonly property alias screen: screenBox

    readonly property bool keycap: theme ? theme.keycap : false
    readonly property real stick: buttons ? (keycap ? 4 : 2) : 0
    readonly property real dropY: keycap ? Math.round(theme.shadowDy * 1.5) : 0
    readonly property real outlineW: keycap ? theme.outlineW : 1
    readonly property real rimW: keycap ? theme.ringW : 0
    readonly property real bezelW: keycap ? 6 : 5
    readonly property real inset: outlineW + rimW + bezelW
    readonly property real bodyW: width - 2 * stick
    readonly property real bodyH: height - dropY
    readonly property real radius: Math.min(56, Math.round(bodyW * 0.13))
    readonly property real screenRadius: Math.max(10, radius - inset)
    // The status row is as tall as the screen's corner, so content below it is never cut by the corner.
    readonly property real statusH: Math.max(34, Math.round(screenRadius))
    readonly property real homeH: homeBar ? 18 : 6
    // Everything that is not content, along the height.
    readonly property real chromeH: dropY + 2 * inset + statusH + homeH
    readonly property real chromeW: 2 * (stick + inset)
    readonly property color lineC: theme ? theme.line : "#121120"

    implicitHeight: chromeH + contentHeight

    // ---- the side buttons, under the body: a rocker on the left, power on the right ----
    Repeater {
        model: ph.buttons ? [[0, 0.17, 0.07], [0, 0.26, 0.07], [1, 0.21, 0.11]] : []
        delegate: Rectangle {
            required property var modelData
            x: modelData[0] === 0 ? 0 : ph.width - width
            y: Math.round(ph.bodyH * modelData[1])
            width: ph.stick + 8
            height: Math.round(ph.bodyH * modelData[2])
            radius: 2
            color: ph.lineC
            antialiasing: true
        }
    }

    // ---- the body ----
    Rectangle {
        visible: ph.dropY > 0
        x: ph.stick
        y: ph.dropY
        width: ph.bodyW
        height: ph.bodyH
        radius: ph.radius
        color: ph.lineC
        antialiasing: true
    }
    Rectangle {
        id: body
        x: ph.stick
        width: ph.bodyW
        height: ph.bodyH
        radius: ph.radius
        // Keycap: the outline, then the rim (ring) inside it. Flat: the bezel itself, with a hairline.
        color: ph.keycap ? ph.theme.ring : ph.lineC
        border.width: ph.outlineW
        border.color: ph.keycap ? ph.lineC : (ph.theme ? ph.theme.outline : "#5a5560")
        antialiasing: true

        // The glass between the rim and the screen (keycap; flat chrome has the body as its bezel).
        Rectangle {
            visible: ph.keycap
            anchors.fill: parent
            anchors.margins: ph.outlineW + ph.rimW
            radius: Math.max(0, ph.radius - ph.outlineW - ph.rimW)
            color: ph.lineC
            antialiasing: true
        }
    }

    // ---- the screen ----
    Rectangle {
        id: screenBox
        x: ph.stick + ph.inset
        y: ph.inset
        width: ph.bodyW - 2 * ph.inset
        height: ph.bodyH - 2 * ph.inset
        radius: ph.screenRadius
        color: ph.screenColor
        antialiasing: true

        Item {
            id: area
            y: ph.statusH
            width: screenBox.width
            height: screenBox.height - ph.statusH - ph.homeH
        }

        // The cut-out: a pill in the glass's colour, with a lens at its end.
        Rectangle {
            id: cutout
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round((ph.statusH - height) / 2)
            width: Math.max(72, Math.min(116, Math.round(screenBox.width * 0.28)))
            height: 22
            radius: height / 2
            color: ph.lineC
            antialiasing: true
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 7
                width: 8
                height: 8
                radius: 4
                color: Qt.lighter(ph.lineC, 1.9)
                antialiasing: true
            }
        }
        // The status row: the caller's items beside the cut-out, clear of the screen's corners.
        Row {
            id: leftSlot
            x: Math.round(ph.screenRadius * 0.55) + 6
            height: ph.statusH
            width: cutout.x - x - 8
            spacing: 4
        }
        Row {
            id: rightSlot
            anchors.right: parent.right
            anchors.rightMargin: Math.round(ph.screenRadius * 0.55) + 6
            height: ph.statusH
            spacing: 4
            layoutDirection: Qt.LeftToRight
        }

        // The home indicator.
        Rectangle {
            visible: ph.homeBar
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round((ph.homeH - height) / 2)
            width: Math.round(screenBox.width * 0.34)
            height: 5
            radius: 2.5
            color: ph.theme ? ph.theme.fg : "#e9e4d8"
            opacity: 0.45
            antialiasing: true
        }
    }
}
