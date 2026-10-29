import QtQuick
import "../../../core"

// The contract of a start-button dress (`[slots] start`, W53.0a): StartHost sets these. `label` is "" unless the look
// shows it (`[decor] start.label`); `vertical` on a side bar. Sized by its implicit size within the bar's height.
Item {
    property string label: ""
    property bool pressed: false
    property bool open: false
    property bool vertical: false
    implicitHeight: Theme.controlH
}
