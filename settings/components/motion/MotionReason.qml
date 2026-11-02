import QtQuick
import "../../core"
import ".."

// One reason line under a motion control (reasons.js `extra`): the daemon's words, with the link to the setting that
// controls it when it names one, as SettingRow's own reason lines read.
Row {
    id: rl
    // {text: i18n key, key} or null
    property var reason: null
    signal openKey(string key)
    visible: rl.reason !== null
    spacing: Theme.gap
    MotionText {
        width: Math.min(implicitWidth, (rl.parent ? rl.parent.width : 480) - (link.visible ? link.width + Theme.gap : 0))
        small: true
        color: Theme.dim
        text: rl.reason ? "⊘ " + I18n.tr(rl.reason.text) : ""
    }
    LinkText {
        id: link
        visible: !!rl.reason && rl.reason.key !== ""
        text: I18n.tr("settings.ui.open")
        onActivated: rl.openKey(rl.reason.key)
    }
}
