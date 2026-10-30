import QtQuick
import "../../../core"

// The contract of a start-button dress (`[slots] start`, W53.0a): StartHost sets these. `label` is "" unless the look
// shows it (`[decor] start.label`); `vertical` on a side bar. Sized by its implicit size within the bar's height. The bar
// module owns the click (it lays its own pointer area over the dress): a dress only draws.
// W53 integration (contract row 563): `menu` names the dress's start-menu skin (a file beside it, e.g.
// `Qt.resolvedUrl("Win95Menu.qml")`, contract start/StartMenuBase.qml) that the launcher draws round its rows while the
// look dresses a start button; "" = the launcher's own start-menu layout in the look's chrome.
Item {
    property string label: ""
    property bool pressed: false
    property bool open: false
    property bool vertical: false
    property url menu: ""
    implicitHeight: Theme.controlH
}
