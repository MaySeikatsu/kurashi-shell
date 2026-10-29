import QtQuick
import "../../../core"
import "../.."
import ".."

// Caption (W53.0a): a window title bar drawn from the look's `[decor] title.*` metrics alone, so 9x, XP, 7 and the Macs
// share it with their own numbers (docs/ux/styles.md: win95 and kawaii both use a caption): a solid or gradient fill
// (`title.fill`, `title.fill_inactive` while the window is not focused; `title.fill_dir`), the text in `title.on` at
// `title.weight`, aligned `title.align`, and the buttons on `title.buttons`' side, each in the `title.close` chrome
// (glyph, bevel, gel, plate, dot). Only buttons that act are drawn (TitleBase). Static (0 frames idle).
TitleBase {
    id: cap
    readonly property var fills: Theme.decor(active ? "title.fill" : "title.fill_inactive", [])
    readonly property color from: fills.length > 0 ? fills[0] : Theme.accent
    readonly property color to: fills.length > 1 ? fills[1] : from
    readonly property color ink: Theme.decor("title.on", "") !== "" ? Theme.decor("title.on", "") : Theme.fgOnAccent
    readonly property string face: Theme.decor("title.close", "glyph")
    readonly property bool startSide: Theme.decor("title.buttons", "end") === "start"
    readonly property real r: Math.max(0, Theme.decor("title.radius", -1))
    readonly property real btn: Math.max(12, height - 6)
    // The buttons, nearest the edge first: close, then the caller's.
    readonly property var names: (canClose ? ["close"] : []).concat(buttons || [])

    Rectangle {
        anchors.fill: parent
        radius: cap.r
        gradient: Gradient {
            orientation: Theme.decor("title.fill_dir", "horizontal") === "vertical" ? Gradient.Vertical : Gradient.Horizontal
            GradientStop { position: 0; color: cap.from }
            GradientStop { position: 1; color: cap.to }
        }
    }
    Row {
        id: lead
        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: cap.startSide ? cap.btnRow : 4 }
        spacing: 4
        Icon {
            visible: cap.icon !== ""
            name: cap.icon
            size: Math.round(cap.height * 0.7)
            color: cap.ink
        }
    }
    readonly property real btnRow: names.length * (btn + 2) + 4
    Text {
        anchors {
            verticalCenter: parent.verticalCenter
            left: lead.right; leftMargin: 4
            right: parent.right; rightMargin: cap.startSide ? 4 : cap.btnRow
        }
        text: cap.title
        color: cap.ink
        elide: Text.ElideRight
        horizontalAlignment: Theme.decor("title.align", "start") === "center" ? Text.AlignHCenter : Text.AlignLeft
        font.family: Theme.fam(cap.title, Theme.families)
        font.pixelSize: Theme.fs
        font.weight: Theme.decor("title.weight", 700)
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
    }
    Row {
        anchors { verticalCenter: parent.verticalCenter; right: cap.startSide ? undefined : parent.right
                  left: cap.startSide ? parent.left : undefined; margins: 3 }
        layoutDirection: cap.startSide ? Qt.LeftToRight : Qt.RightToLeft
        spacing: 2
        Repeater {
            model: cap.names
            Item {
                id: b
                required property string modelData
                width: cap.btn
                height: cap.face === "bevel" ? cap.btn - 2 : cap.btn
                readonly property bool round: cap.face === "gel" || cap.face === "dot"
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("decor.title." + modelData)
                Rectangle {
                    anchors.fill: parent
                    visible: cap.face !== "glyph"
                    radius: b.round ? width / 2 : (cap.face === "plate" ? 3 : 0)
                    color: b.modelData === "close" && cap.face !== "bevel" ? Theme.error : Theme.container
                    border.width: cap.face === "plate" ? 1 : 0
                    border.color: Qt.alpha(cap.ink, 0.6)
                    // A gel's light upper half.
                    Rectangle {
                        visible: cap.face === "gel"
                        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 2 }
                        height: parent.height / 2 - 2
                        radius: height / 2
                        color: Qt.rgba(1, 1, 1, 0.35)
                    }
                    BevelEdge {
                        anchors.fill: parent
                        visible: cap.face === "bevel"
                        w: Theme.crisp(1, Screen.devicePixelRatio)
                        sunk: hit.pressed
                    }
                }
                Icon {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: cap.face === "bevel" && hit.pressed ? 1 : 0
                    anchors.verticalCenterOffset: cap.face === "bevel" && hit.pressed ? 1 : 0
                    // A dot shows its mark only under the pointer (the Macs).
                    visible: cap.face !== "dot" || hit.containsMouse
                    name: b.modelData === "close" ? "close" : b.modelData === "maximize" ? "crop_square" : "minimize"
                    glyph: b.modelData === "close" ? "×" : b.modelData === "maximize" ? "□" : "_"
                    size: Math.round(b.height * 0.8)
                    color: cap.face === "bevel" || cap.face === "plate" ? Theme.fg : (cap.face === "glyph" ? cap.ink : Theme.fgOnAccent)
                }
                MouseArea {
                    id: hit
                    anchors.fill: parent
                    hoverEnabled: cap.face === "dot"
                    onClicked: b.modelData === "close" ? cap.close() : cap.button(b.modelData)
                }
            }
        }
    }
}
