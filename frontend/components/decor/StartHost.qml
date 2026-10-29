import QtQuick
import "../../core"

// StartHost (W53.0a, K80): the look's start-button dress (`[slots] start`) for the bar's launcher toggle (the `launcher`
// module, W53.0b): an original mark, never a vendor's logo, and with `[decor] start.label` the label
// (`decor.start.label`, i18n). Contract: `start/StartBase.qml`. Without a start slot nothing is made: the module draws
// its plain icon button. The module owns the action (the dress only draws `pressed` and `open`).
DecorHost {
    id: sh
    slot: "start"
    property bool pressed: false
    property bool open: false
    property bool vertical: false
    implicitWidth: ready ? item.implicitWidth : 0
    implicitHeight: ready ? item.implicitHeight : 0
    onLoaded: {
        item.label = Qt.binding(function () { return Theme.decor("start.label", false) ? I18n.tr("decor.start.label") : "" })
        item.pressed = Qt.binding(function () { return sh.pressed })
        item.open = Qt.binding(function () { return sh.open })
        item.vertical = Qt.binding(function () { return sh.vertical })
    }
}
