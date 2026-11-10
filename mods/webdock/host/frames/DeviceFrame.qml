import QtQuick
import QtQuick.Effects

// The web dock's phone and its tablet (W69, I468; docs/ux/webdock.md "Page styles" › Phone): PhoneFrame's phone seen
// from the front (K42, frontend/components/phone/PhoneFrame.qml, whose token rules this follows line for line) with one
// more input, `wide`: 0 the phone, 1 a tablet lying sideways. Between them every part moves continuously — the corner
// radius, the bezel, the cut-out (the pill narrows into a camera dot on the long top bezel), the status row, the side
// buttons (the phone's rocker and power leave the long sides, the tablet's pair stands on its top edge) — so the size
// change is one morph of one body, not a swap. Static at rest (no timer, no animation of its own: the card drives
// `wide`, Ma). Drawn from tokens only (rule 4). Shared by the web host and the shell's card (mods/webdock/qml/frames is a
// link here): it imports nothing of either, takes the caller's Theme (`theme`) and the caller's RoundBox and Relief by
// component and URL (`box`, `reliefUrl`; none = a plain Rectangle, no relief).
Item {
    id: ph

    property var theme: null
    property real wide: 0
    property Component box: null
    property url reliefUrl: ""
    property bool buttons: true
    property bool homeBar: true
    property color screenColor: theme ? theme.surface : "#1b1a1e"
    property alias statusLeft: leftSlot.data
    property alias statusRight: rightSlot.data
    readonly property alias screen: screenBox

    readonly property real w: Math.max(0, Math.min(1, wide))
    function mix(a, b) { return a + (b - a) * w }
    // The chrome (PhoneFrame's rules): a ring makes the keycap device; an outline without either shadow draws it.
    readonly property bool keycap: theme ? theme.ringW > 0 : false
    readonly property bool drawn: theme ? theme.outlineW > 0 && theme.shadowDy <= 0 && theme.softR <= 0 : false
    readonly property real stick: buttons ? (keycap ? 4 : 2) : 0
    readonly property real castX: keycap ? Math.round(theme.sinkX * 1.5) : 0
    readonly property real castY: keycap ? Math.round(theme.sinkY * 1.5) : 0
    readonly property real dropY: keycap ? Math.round(theme.shadowDy * 1.5) : 0
    readonly property real softPad: theme && theme.softR > 0 ? Math.round(theme.softR * 0.6) : 0
    readonly property real softFoot: theme && theme.softR > 0 ? softPad + theme.softDy : 0
    // Room for the buttons: on the long sides for the phone, on the top edge for the tablet.
    readonly property real side: mix(stick, 0) + softPad
    readonly property real topRoom: mix(0, stick)
    readonly property real outlineW: theme && theme.outlineW > 0 ? theme.outlineW : 1
    readonly property real rimW: keycap ? theme.ringW : 0
    readonly property real bezelW: mix(keycap ? 6 : (drawn ? 4 : 5), keycap ? 10 : (drawn ? 7 : 9))
    readonly property color edgeC: keycap ? lineC : (theme ? (theme.outlineW > 0 ? theme.outlineColor : theme.outline) : "#5a5560")
    readonly property real inset: outlineW + rimW + bezelW
    readonly property real bodyW: width - 2 * side
    readonly property real bodyH: height - topRoom - dropY - softFoot
    readonly property real k: theme ? Math.max(0.3, Math.min(1, theme.rLg / 18)) : 1
    // A phone's corners (PhoneFrame's), a tablet's rounder-but-smaller ones relative to its size.
    readonly property real radius: Math.round(k * mix(Math.min(56, bodyW * 0.13), Math.min(40, Math.min(bodyW, bodyH) * 0.06)))
    readonly property real screenRadius: Math.max(8, radius - inset)
    // The status row is as tall as the screen's corner (the phone); the tablet's is a slim row under its smaller corner.
    readonly property real statusH: Math.round(mix(Math.max(34, screenRadius), 28))
    readonly property real homeH: homeBar ? 18 : 6
    readonly property color lineC: theme ? theme.line : "#121120"

    // ---- the buttons: the phone's on its long sides, the tablet's on its top edge ----
    Repeater {
        model: ph.buttons ? [[0, 0.17, 0.07], [0, 0.26, 0.07], [1, 0.21, 0.11]] : []
        delegate: Rectangle {
            required property var modelData
            visible: ph.w < 0.5
            opacity: 1 - 2 * ph.w
            x: modelData[0] === 0 ? ph.softPad : ph.width - ph.softPad - width
            y: ph.topRoom + Math.round(ph.bodyH * modelData[1])
            width: ph.stick + 8
            height: Math.round(ph.bodyH * modelData[2])
            radius: 2
            color: ph.drawn ? ph.edgeC : ph.lineC
            antialiasing: true
        }
    }
    Repeater {
        // The tablet's power (near its left end) and its volume rocker (near its right end), along the top edge.
        model: ph.buttons ? [[0.08, 0.05], [0.78, 0.05], [0.84, 0.05]] : []
        delegate: Rectangle {
            required property var modelData
            visible: ph.w > 0.5
            opacity: 2 * ph.w - 1
            x: ph.side + Math.round(ph.bodyW * modelData[0])
            y: 0
            width: Math.round(ph.bodyW * modelData[1])
            height: ph.stick + 8
            radius: 2
            color: ph.drawn ? ph.edgeC : ph.lineC
            antialiasing: true
        }
    }

    // ---- the body ----
    Loader {
        x: ph.side
        y: ph.topRoom
        width: ph.bodyW
        height: ph.bodyH
        active: ph.theme !== null && ph.theme.softR > 0
        sourceComponent: RectangularShadow {
            offset.x: ph.theme.shadowX
            offset.y: ph.theme.shadowY
            blur: ph.theme.softR
            spread: -1
            radius: ph.radius
            color: ph.theme.softColor
        }
    }
    FrameBox {
        box: ph.box
        visible: ph.castX !== 0 || ph.castY !== 0
        x: ph.side + ph.castX
        y: ph.topRoom + ph.castY
        width: ph.bodyW
        height: ph.bodyH
        radius: ph.radius
        color: ph.lineC
    }
    FrameBox {
        box: ph.box
        x: ph.side
        y: ph.topRoom
        width: ph.bodyW
        height: ph.bodyH
        radius: ph.radius
        color: ph.keycap ? ph.theme.ring : (ph.drawn ? ph.screenColor : ph.lineC)
        borderWidth: ph.outlineW
        borderColor: ph.edgeC
    }
    // The glass between the rim and the screen (keycap).
    FrameBox {
        box: ph.box
        visible: ph.keycap
        x: ph.side + ph.outlineW + ph.rimW
        y: ph.topRoom + ph.outlineW + ph.rimW
        width: ph.bodyW - 2 * (ph.outlineW + ph.rimW)
        height: ph.bodyH - 2 * (ph.outlineW + ph.rimW)
        radius: Math.max(0, ph.radius - ph.outlineW - ph.rimW)
        color: ph.lineC
    }

    // ---- the screen ----
    Item {
        id: screenBox
        x: ph.side + ph.inset
        y: ph.topRoom + ph.inset
        width: ph.bodyW - 2 * ph.inset
        height: ph.bodyH - 2 * ph.inset
        FrameBox {
            box: ph.box
            anchors.fill: parent
            radius: ph.screenRadius
            color: ph.screenColor
            borderWidth: ph.drawn ? ph.outlineW : 0
            borderColor: ph.edgeC
        }
        // K59 (I172): the screen's ground is a material area where the caller's theme has a texture (the shell's).
        Loader {
            z: ph.theme && ph.theme.texText === true ? 1 : 0
            anchors.fill: parent
            anchors.margins: ph.drawn ? ph.outlineW : 0
            active: !!ph.theme && ph.theme.texShell === true && ph.reliefUrl.toString() !== ""
            source: active ? ph.reliefUrl : ""
            onLoaded: item.radius = Qt.binding(function () { return Math.max(0, ph.screenRadius - (ph.drawn ? ph.outlineW : 0)) })
        }
        // The status row: the caller's items, clear of the screen's corners and the cut-out.
        Row {
            id: leftSlot
            x: Math.round(ph.screenRadius * 0.55) + 6
            height: ph.statusH
            width: Math.max(0, screenBox.width / 2 - 70 - x)
            spacing: 4
        }
        Row {
            id: rightSlot
            anchors.right: parent.right
            anchors.rightMargin: Math.round(ph.screenRadius * 0.55) + 6
            height: ph.statusH
            spacing: 4
        }
        // The home indicator.
        Rectangle {
            visible: ph.homeBar
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round((ph.homeH - height) / 2)
            width: Math.round(ph.mix(screenBox.width * 0.34, Math.min(screenBox.width * 0.18, 320)))
            height: 5
            radius: 2.5
            color: ph.theme ? ph.theme.fg : "#e9e4d8"
            opacity: 0.45
            antialiasing: true
        }
    }
    // The cut-out: the phone's pill in the status row, narrowing into the tablet's camera dot in the top bezel's middle.
    Rectangle {
        id: cutout
        z: 2
        readonly property real pillW: Math.max(72, Math.min(116, Math.round(screenBox.width * 0.28)))
        width: Math.round(ph.mix(pillW, 9))
        height: Math.round(ph.mix(22, 9))
        x: screenBox.x + (screenBox.width - width) / 2
        // (phone: the status row's middle, on the screen; tablet: the top bezel's middle)
        y: Math.round(ph.mix(screenBox.y + (ph.statusH - 22) / 2, ph.topRoom + (ph.inset - 9) / 2 + 1))
        radius: height / 2
        color: ph.drawn ? "transparent" : ph.lineC
        border.width: ph.drawn ? ph.outlineW : 0
        border.color: ph.edgeC
        antialiasing: true
        // The lens: at the pill's end on the phone, the dot itself on the tablet.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: ph.mix(cutout.width - 7 - width, (cutout.width - width) / 2)
            width: Math.round(ph.mix(8, 5))
            height: width
            radius: width / 2
            color: ph.drawn ? ph.edgeC : Qt.lighter(ph.lineC, 1.9)
            antialiasing: true
        }
    }
}
