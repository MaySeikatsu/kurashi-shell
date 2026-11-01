import QtQuick
import "../../../core"
import ".."

// Filigree (W53.6): an ornate menu's selected row — Hollow Knight's (docs/ux/styles.md §9.4): no band, the row framed by a
// pair of marks (`[decor] menu.mark`, a fleur by default: Bullet.qml, original) at its two ends pointing in, in
// `menu.line` ("" = `menu.on`, else the text's ink); with `menu.fill` a faint band fading toward both ends. The pair sweeps
// in from the row's ends once as the row lights (the look's fast time; at once under reduce motion), then rests. A
// separator is a short faded hairline. Colours from roles (rule 4); idle = 0 frames.
MenuRowBase {
    id: row
    readonly property string lineRole: Theme.decor("menu.line", "")
    readonly property string onRole: Theme.decor("menu.on", "")
    readonly property color ink: lineRole !== "" ? lineRole : onRole !== "" ? onRole : Theme.fg
    readonly property string fillRole: Theme.decor("menu.fill", "")
    readonly property color band: fillRole !== "" ? fillRole : "transparent"
    readonly property string kind: Theme.decor("menu.mark", "none") !== "none" ? Theme.decor("menu.mark", "none") : "fleur"
    readonly property bool lit: highlighted && enabled && !separator
    readonly property bool moves: Theme.motionKind !== "none"
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property real s: Math.max(6, Math.min(8, Math.round(height * 0.18)))
    // 0 = the marks out at the ends and clear, 1 = in place.
    property real reach: lit ? 1 : 0
    Behavior on reach {
        enabled: row.moves
        NumberAnimation { duration: Math.max(120, Theme.fastMs); easing.type: Easing.OutCubic }
    }

    Rectangle {
        visible: row.lit && row.fillRole !== ""
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(row.band, 0) }
            GradientStop { position: 0.5; color: Qt.alpha(row.band, 0.35) }
            GradientStop { position: 1; color: Qt.alpha(row.band, 0) }
        }
    }
    Bullet {
        visible: row.reach > 0
        opacity: row.reach
        kind: row.kind
        size: row.s
        ink: row.ink
        x: 1 - Math.round((1 - row.reach) * row.s)
        anchors.verticalCenter: parent.verticalCenter
    }
    Bullet {
        visible: row.reach > 0
        opacity: row.reach
        kind: row.kind
        size: row.s
        mirror: true
        ink: row.ink
        x: row.width - width - 1 + Math.round((1 - row.reach) * row.s)
        anchors.verticalCenter: parent.verticalCenter
    }
    Rectangle {
        visible: row.separator
        anchors.centerIn: parent
        width: parent.width * 0.6
        height: row.hair
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(row.ink, 0) }
            GradientStop { position: 0.5; color: Qt.alpha(row.ink, 0.6) }
            GradientStop { position: 1; color: Qt.alpha(row.ink, 0) }
        }
    }
}
