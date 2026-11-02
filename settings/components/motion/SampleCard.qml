import QtQuick
import "../../core"
import ".."

// A surface class's sample card on the preview stage (W59.6b): what that class looks like on the shell, in miniature — a card
// on the look's surface fill (translucent where the look is: the panel alpha) with its outline and corners, its title and a
// few lines of content as bars. The content arrives as the shell's does (brief §7: late, with, cascade) from the one
// progress, through the shell's own Stagger. Static: it draws nothing by itself (Ma).
RoundBox {
    id: sc
    property string surface: "panel"
    property real progress: 1
    property string content: "late"
    property real staggerMs: 0
    property real durationMs: 0

    property bool thin: height < 48
    radius: sc.surface === "sidebar" ? 0 : sc.thin ? height / 2 : Math.min(Theme.rLg, height / 4)
    color: Qt.alpha(Theme.surface, Theme.panel.a)
    border.width: 1
    border.color: Theme.outline

    // The rows that arrive one after another (title, lines, tiles).
    readonly property int rows: sc.thin ? 2 : Math.max(2, Math.min(6, Math.floor((sc.height - 34) / 18)))
    Stagger {
        id: stg
        progress: sc.progress
        count: sc.rows + 1
        content: sc.content
        staggerMs: sc.staggerMs
        durationMs: sc.durationMs
    }
    readonly property string title: I18n.tr("motion.ui.preview.class." + sc.surface)

    // A thin card (a peek, an on-screen display, the bar): a glyph, the name and a level.
    Row {
        visible: sc.thin
        anchors.verticalCenter: parent.verticalCenter
        x: 12
        spacing: 8
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 14; height: 14; radius: 7
            color: Theme.accent
            opacity: stg.at(0)
        }
        MotionText {
            anchors.verticalCenter: parent.verticalCenter
            small: true
            wrapMode: Text.NoWrap
            text: sc.title
            opacity: stg.at(1)
        }
        // The bar: its modules as pills.
        Repeater {
            model: sc.surface === "bar" ? 6 : 0
            delegate: Rectangle {
                required property int index
                anchors.verticalCenter: parent.verticalCenter
                width: [44, 30, 56, 36, 28, 40][index]; height: 12; radius: 6
                color: Theme.containerHigh
                opacity: stg.at(2)
            }
        }
        Rectangle {
            visible: sc.surface !== "bar"
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(20, sc.width - 60 - sc.titleW)
            height: 4; radius: 2
            color: Theme.containerHigh
            opacity: stg.at(2)
            Rectangle { width: parent.width * 0.6; height: parent.height; radius: 2; color: Theme.accent }
        }
    }
    readonly property real titleW: Math.min(120, I18n.tr("motion.ui.preview.class." + sc.surface).length * 7)

    // A card: the title, then lines (a menu: items; a toast: a glyph beside two lines).
    Column {
        visible: !sc.thin
        x: 12
        y: 10
        width: sc.width - 24
        spacing: 8
        Row {
            spacing: 8
            opacity: stg.at(0)
            Rectangle {
                visible: sc.surface === "toast" || sc.surface === "dialog"
                width: 22; height: 22; radius: sc.surface === "toast" ? 11 : 6
                color: Theme.accent
            }
            MotionText { font.weight: Font.DemiBold; wrapMode: Text.NoWrap; text: sc.title }
        }
        Repeater {
            model: sc.rows - 1
            delegate: Rectangle {
                required property int index
                width: sc.surface === "menu" ? sc.width - 24 : (sc.width - 24) * [0.92, 0.74, 0.85, 0.6, 0.8][index % 5]
                height: sc.surface === "menu" ? 12 : 6
                radius: height / 2
                color: sc.surface === "menu" && index === 0 ? Theme.selected : Theme.containerHigh
                opacity: stg.at(index + 1)
                Rectangle {
                    visible: sc.surface !== "menu"
                    width: parent.width * 0.35; height: parent.height; radius: parent.radius
                    color: Theme.dim
                    opacity: 0.6
                }
            }
        }
    }
}
