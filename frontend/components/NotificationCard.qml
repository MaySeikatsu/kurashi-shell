import QtQuick
import Quickshell
import "../core"

// One notification, shared by the toast stack and the center. Presentational: `item` is an entry
// of svc.notifications.items; signals out. Body is the daemon-sanitised b/i/u/a subset, so
// StyledText is safe. Swipe right (or the close control) dismisses; actions are the app's own.
// Keyboard: the close control and the actions take Tab focus; Return, Enter and Space press them.
Rectangle {
    id: c
    property var item: ({})
    property bool swipeable: true
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
    color: Theme.container
    border.width: 1
    border.color: urgent ? Theme.accent : Theme.outline
    // Only a dragged or snapping card has opacity < 1, so static cards never pay for group opacity (K16).
    opacity: drag.active || snap.running ? Math.max(0.3, 1 - Math.abs(x) / width) : 1

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
        width: parent.width - 2 * Theme.pad
        spacing: Theme.gap
        Image {
            id: img
            visible: c.icon !== "" && status === Image.Ready
            width: visible ? 32 : 0
            height: 32
            sourceSize: Qt.size(64, 64)
            source: c.icon
            asynchronous: true
            fillMode: Image.PreserveAspectFit
        }
        Column {
            id: col
            width: parent.width - (img.visible ? img.width + parent.spacing : 0) - closeBtn.width - parent.spacing
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
                font.bold: true
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
                        radius: Theme.rSm
                        color: Theme.containerHigh
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
            Text {
                anchors.centerIn: parent
                color: Theme.dim
                font.pixelSize: Theme.fs
                text: "✕"
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
