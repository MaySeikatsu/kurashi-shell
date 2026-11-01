import QtQuick
import "../../../core"
import "../.."
import ".."

// Fluent (W53.3, docs/ux/styles.md §4): Windows 11's start button — a 40 × 40 key on the taskbar (`thickness − 8`: 40 in
// the 48 px bar of `fluent-desk`), transparent at rest, a subtle plate with 4 px corners under the pointer and while the
// menu is open, the mark shrinking a little while pressed (11's press feedback). The mark is original: four panes with
// rounded corners, each its own tone of the accent (light at the top left, deepest at the bottom right) — not the
// vendor's flat logo. Its start-menu skin is `FluentMenu.qml`. Drawn from tokens only (rule 4); static at rest.
StartBase {
    id: st
    property real thickness: Theme.barH
    signal clicked()

    readonly property bool down: pressed || hit.pressed
    readonly property bool lit: open || hit.containsMouse
    implicitHeight: Math.max(24, Math.round(thickness) - 8)
    implicitWidth: implicitHeight
    width: implicitWidth
    height: implicitHeight
    menu: Qt.resolvedUrl("FluentMenu.qml")

    Accessible.role: Accessible.Button
    Accessible.name: I18n.tr("layout.module.launcher")
    Accessible.onPressAction: st.clicked()

    // The plate: ControlFillColorDefault-like over the bar (the container's high step), a 1 px hairline as 11 draws it.
    Rectangle {
        anchors.fill: parent
        visible: st.lit || st.down
        radius: Theme.rSm
        color: Qt.alpha(Theme.containerHigh, st.down ? 0.55 : 0.8)
        border.width: 1
        border.color: Qt.alpha(Theme.fg, 0.06)
    }
    Item {
        id: mark
        readonly property int side: Math.round(st.height * 0.45)
        readonly property real gap: Math.max(1, Math.round(side / 10))
        readonly property real pane: (side - gap) / 2
        readonly property color base: Theme.accent
        width: side
        height: side
        anchors.centerIn: parent
        scale: st.down ? 0.86 : 1
        Behavior on scale {
            enabled: Theme.timed
            NumberAnimation { duration: Theme.fastMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.fastCurve }
        }
        Repeater {
            model: 4
            Rectangle {
                id: paneR
                required property int index
                readonly property int col: index % 2
                readonly property int row: Math.floor(index / 2)
                // Lighter toward the top left: each pane a step of its own along the diagonal.
                readonly property real lift: 0.16 * (2 - col - row)
                readonly property color inkTop: Qt.lighter(mark.base, 1.25 + lift)
                readonly property color inkBottom: Qt.lighter(mark.base, 1.0 + lift)
                x: col * (mark.pane + mark.gap)
                y: row * (mark.pane + mark.gap)
                width: mark.pane
                height: mark.pane
                radius: Math.max(1, mark.pane / 5)
                gradient: Gradient {
                    GradientStop { position: 0; color: paneR.inkTop }
                    GradientStop { position: 1; color: paneR.inkBottom }
                }
            }
        }
    }
    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        onClicked: st.clicked()
    }
}
