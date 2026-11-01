import QtQuick
import QtQuick.Shapes
import "../../../core"

// Margin (W53.7, docs/ux/styles.md §9 kami, K60): a menu written on a notebook page — the red margin rule runs down
// every row at the row's lead (`[decor] menu.lead`: the content starts right of it, as writing starts right of a
// notebook's margin), so a menu shows one unbroken rule; the chosen row is underlined by hand in the red correction pen
// (a stroke that dips a little and lifts at its end, thicker in its middle); a separator is a pencil dash line between
// the rule and the row's end. Roles only (rule 4): the rule and the underline are the accent (the red pen), the pencil
// the text's ink thinned. Static: each row draws once; the underline is made only on the chosen row.
MenuRowBase {
    id: row
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property real lead: Math.max(8, Theme.decor("menu.lead", 0) * Theme.pixelScale)
    readonly property real ruleX: Math.round(lead - 5)

    // The margin rule (a red pen line, slightly translucent as ink on paper).
    Rectangle {
        x: row.ruleX
        // (past the row's foot: callers leave a px or two between rows, the rule runs on through them)
        anchors { top: parent.top; bottom: parent.bottom; topMargin: -3; bottomMargin: -3 }
        width: row.hair
        color: Qt.alpha(Theme.accent, 0.7)
    }
    // A separator: pencil dashes.
    Row {
        visible: row.separator
        x: row.ruleX + 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Repeater {
            model: row.separator ? Math.max(0, Math.floor((row.width - row.ruleX - 16) / 10)) : 0
            Rectangle { width: 6; height: row.hair; color: Qt.alpha(Theme.fg, 0.4) }
        }
    }
    // The chosen row's underline.
    Loader {
        active: row.highlighted && row.enabled && !row.separator
        x: row.ruleX + 10
        width: Math.min(row.width - x - 12, Math.max(120, (row.width - x) * 0.45))
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3
        height: 7
        sourceComponent: Shape {
            id: ul
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"
                fillColor: Theme.accent
                startX: 0; startY: 3.6
                PathCubic { x: ul.width; y: 2.2; control1X: ul.width * 0.3; control1Y: 4.6; control2X: ul.width * 0.72; control2Y: 2.2 }
                PathCubic { x: 0; y: 3.6; control1X: ul.width * 0.7; control1Y: 5.4; control2X: ul.width * 0.32; control2Y: 7.4 }
            }
        }
    }
}
