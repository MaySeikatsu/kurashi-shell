import QtQuick
import "../core"

// FieldLine (W53.5, `[decor] field.form = underline`): the line a text field stands on instead of a box. On a pixel grid
// (snes) a name-entry line — whole grid pixels in the window's ink, no antialiasing; otherwise a hairline (the PS2's) that
// takes the accent and, while the look glows (`Theme.glow`), a soft rise of light above it while the field has the
// keyboard; `error` turns it the error role. Static: it changes with focus only.
Item {
    id: fl
    property bool focused: false
    property bool error: false
    readonly property int g: Theme.grid(Screen.height)
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property color ink: error ? Theme.error : (focused ? (g > 0 ? Theme.fg : Theme.accent) : Qt.alpha(Theme.fg, 0.55))
    height: g > 0 ? g : 2 * hair
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: fl.g > 0 ? fl.g : fl.hair
        antialiasing: fl.g <= 0
        color: fl.ink
    }
    Rectangle {
        visible: fl.g <= 0 && Theme.glow > 0 && (fl.focused || fl.error)
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: fl.hair }
        height: 10
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Qt.alpha(fl.error ? Theme.error : Theme.glowColor, 0.35 * Math.min(1, Theme.glow * 2)) }
        }
    }
}
