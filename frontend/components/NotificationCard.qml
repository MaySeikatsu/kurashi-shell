import QtQuick
import Quickshell
import "../core"

// One notification, shared by the toast stack and the center. Presentational: `item` is an entry
// of svc.notifications.items; signals out. Body is the daemon-sanitised b/i/u/a subset, so
// StyledText is safe. Swipe right (or the close control) dismisses; actions are the app's own.
// Keyboard: the close control and the actions take Tab focus; Return, Enter and Space press them.
// W34: a budding toast's chrome (fill, outline, shadows, material) is drawn by its shape (Toasts.qml) until it stands
// free: `bare` leaves only the content, `contentOpacity` fades it in late; `carryDy` is how far the card is from its
// place at rest (K61: its relief carries the sheet along while the stack springs).
RoundBox {
    id: c
    property var item: ({})
    property bool swipeable: true
    property bool bare: false
    property real contentOpacity: 1
    property real carryDy: 0
    signal dismissed()
    signal invoked(string key)

    readonly property bool urgent: item.urgency === "critical"
    readonly property string icon: {
        var s = item.image || item.app_icon || ""
        if (s === "") return ""
        if (s.charAt(0) === "/" || s.indexOf("file://") === 0) return s
        return Quickshell.iconPath(s, true)
    }

    width: 340
    implicitHeight: row.height + 2 * Theme.pad
    radius: Theme.rLg
    color: bare ? "transparent" : Theme.panel
    // The chrome's outline (K42, K45: keycap ink, soft rim, line outline; accent when urgent) and its shadow, hard or soft;
    // flat: a hairline.
    // K62: with a pen in effect the pen draws it instead (over the content's edge, like the border it replaces).
    border.width: pen.active || bare ? 0 : (Theme.outlineW > 0 ? Theme.outlineW : 1)
    border.color: urgent ? Theme.accent : (Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline)
    Loader {
        id: pen
        z: 3
        anchors.fill: parent
        active: Theme.penOutline && !c.bare
        sourceComponent: PenOutline {
            radius: c.radius
            color: c.border.color
            lineWidth: Theme.outlineW > 0 ? Theme.outlineW : 1
            // Salted by the notification's id: a card keeps its line while it is swiped, and two cards differ.
            seed: c.item && c.item.id !== undefined ? (Math.imul(Number(c.item.id) | 0, 0x9E3779B1) >>> 1) : 0
        }
    }
    // K59: the card is a material area (the panel's fill); the relief lies under the content. K61: a swiped card carries its
    // sheet along (`texture.sheet = carried`), on top of its window's carry.
    Loader {
        anchors.fill: parent
        anchors.margins: Theme.outlineW
        active: Theme.texShell && !Theme.texText && !c.bare
        sourceComponent: Relief {
            anchors.fill: parent
            radius: Math.max(0, c.radius - Theme.outlineW)
            carry: Qt.point(windowCarry.x + c.x, windowCarry.y + c.carryDy)
        }
    }
    // With `texture.text` the relief lies over the card's text too.
    Loader {
        z: 1
        anchors.fill: parent
        anchors.margins: Theme.outlineW
        active: Theme.texShell && Theme.texText && !c.bare
        sourceComponent: Relief {
            anchors.fill: parent
            radius: Math.max(0, c.radius - Theme.outlineW)
            carry: Qt.point(windowCarry.x + c.x, windowCarry.y + c.carryDy)
        }
    }
    SoftShadow { anchors.fill: parent; radius: c.radius; amount: c.bare ? 0 : 1 }
    // The hard shadow along the shadow vector (K67, docs/ux/shadows.md): none at strength 0 or under flat and line chrome.
    RoundBox {
        z: -1
        visible: (Theme.sinkX !== 0 || Theme.sinkY !== 0) && !c.bare
        x: Theme.sinkX
        y: Theme.sinkY
        width: c.width
        height: c.height
        radius: c.radius
        color: Theme.line
    }
    // Only a dragged, snapping or flicked card has opacity < 1, so static cards never pay for group opacity (K16). A card
    // swiped past the threshold keeps its own while its stack flicks it away (W34).
    opacity: x !== 0 ? Math.max(0.3, 1 - Math.abs(x) / width) : 1

    // A cancelled swipe slides back on the standard motion token (instant under motion none).
    NumberAnimation {
        id: snap
        target: c
        property: "x"
        to: 0
        duration: Theme.stdMs
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.enterCurve
    }

    DragHandler {
        id: drag
        enabled: c.swipeable
        xAxis.enabled: true
        yAxis.enabled: false
        xAxis.minimum: 0
        onActiveChanged: {
            if (active) return
            if (c.x > c.width * 0.35) c.dismissed()
            else snap.restart()
        }
    }

    Row {
        id: row
        x: Theme.pad
        y: Theme.pad
        opacity: c.contentOpacity
        visible: opacity > 0
        width: parent.width - 2 * Theme.pad
        spacing: Theme.gap
        // No picture from the app: its kind as an icon in a tonal disc, so every card has a face.
        Rectangle {
            visible: !img.visible
            width: 32
            height: 32
            radius: Math.min(16, Theme.rFull)
            color: c.urgent ? Theme.accent : Theme.selected
            border.width: Theme.ringW > 0 ? Theme.outlineW : 0
            border.color: Theme.outlineColor
            Icon {
                anchors.centerIn: parent
                name: c.urgent ? "priority_high" : "notifications"
                glyph: c.urgent ? "!" : "•"
                filled: true
                size: 18
                color: c.urgent ? Theme.fgOnAccent : Theme.fgOnSelected
            }
        }
        Image {
            id: img
            visible: c.icon !== "" && status === Image.Ready
            // I167: the notification's own picture (an avatar, a photo) never gets the relief; an app icon is an icon.
            readonly property var pictureOf: (c.item.image || "") !== "" ? Window.window : null
            onPictureOfChanged: pictureOf ? Light.addPicture(img, pictureOf) : Light.removePicture(img)
            Component.onDestruction: Light.removePicture(img)
            width: visible ? 32 : 0
            height: 32
            sourceSize: Qt.size(64, 64)
            source: c.icon
            asynchronous: true
            fillMode: Image.PreserveAspectFit
        }
        Column {
            id: col
            width: parent.width - 32 - parent.spacing - closeBtn.width - parent.spacing
            spacing: Theme.xs
            Text {
                width: parent.width
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                elide: Text.ElideRight
                text: (c.item.app_name || "") + (c.item.time ? "  ·  " + Qt.formatTime(new Date(c.item.time), "hh:mm") : "")
            }
            Text {
                width: parent.width
                visible: text !== ""
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: c.item.summary || ""
            }
            Text {
                width: parent.width
                visible: text !== ""
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                text: c.item.body || ""
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
            Flow {
                width: parent.width
                spacing: Theme.gap
                visible: (c.item.actions || []).length > 0
                Repeater {
                    model: c.item.actions || []
                    delegate: Rectangle {
                        required property var modelData
                        implicitWidth: lbl.implicitWidth + 2 * Theme.pad
                        implicitHeight: 26
                        radius: Theme.groups ? Math.min(height / 2, Theme.rFull) : Theme.rSm
                        // Outlined chrome without a shadow: an outlined box, no fill behind the label.
                        color: Theme.outlineW > 0 && Theme.shadowDy <= 0 && Theme.softR <= 0 ? "transparent" : Theme.containerHigh
                        border.width: Theme.outlineW
                        border.color: Theme.outlineColor
                        activeFocusOnTab: true
                        Keys.onReturnPressed: c.invoked(modelData.key)
                        Keys.onEnterPressed: c.invoked(modelData.key)
                        Keys.onSpacePressed: c.invoked(modelData.key)
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.label
                        Text {
                            id: lbl
                            anchors.centerIn: parent
                            color: Theme.fg
                            font.pixelSize: Theme.fs
                            font.family: Theme.fam(text, Theme.families)
                            text: modelData.label
                        }
                        MouseArea {
                            anchors.fill: parent
                            // The hit area reaches the control height; the pill keeps its size.
                            anchors.topMargin: -Math.max(0, (Theme.controlH - parent.height) / 2)
                            anchors.bottomMargin: -Math.max(0, (Theme.controlH - parent.height) / 2)
                            onClicked: c.invoked(modelData.key)
                        }
                        FocusRing {
                            anchors.fill: parent
                            shown: parent.activeFocus
                            corner: Theme.rSm
                        }
                    }
                }
            }
        }
        Rectangle {
            id: closeBtn
            width: 24
            height: 24
            radius: Theme.rFull
            color: closeHover.hovered ? Theme.containerHigh : "transparent"
            activeFocusOnTab: true
            Keys.onReturnPressed: c.dismissed()
            Keys.onEnterPressed: c.dismissed()
            Keys.onSpacePressed: c.dismissed()
            Accessible.role: Accessible.Button
            Accessible.name: I18n.tr("frontend.notification.dismiss")
            Icon {
                anchors.centerIn: parent
                color: Theme.dim
                name: "close"
                glyph: "✕"
                size: Theme.fs + 3
            }
            HoverHandler { id: closeHover }
            MouseArea {
                anchors.fill: parent
                // The hit area reaches the 32 px floor; the glyph square stays 24 px.
                anchors.margins: -Math.max(0, (Theme.controlH - closeBtn.height) / 2)
                onClicked: c.dismissed()
            }
            FocusRing {
                anchors.fill: parent
                shown: closeBtn.activeFocus
                corner: Theme.rFull
            }
        }
    }
}
