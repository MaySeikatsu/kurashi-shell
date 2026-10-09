import QtQuick
import "../../core"
import "../expanded"
import ".."

// The session footer (docs/ux/quick-settings.md, Design 4). Lock and suspend appear only while the session service answers
// (svc.session `available`, the capability the daemon serves). Lock runs at once; suspend needs a second press within 3 s,
// as the session menu does (the daemon refuses it without `confirm`). The power menu is the existing session panel. There
// is no settings button: no daemon action opens the settings app yet (docs/CONTRACT-CHANGE.md).
Column {
    id: foot
    property bool sessionOk: false
    property bool armed: false
    property string errText: ""
    spacing: Theme.gap
    Refusal { id: refusal }

    Timer {
        interval: 3000
        running: foot.armed
        onTriggered: foot.armed = false
    }
    function act(action, args) {
        foot.errText = ""
        Store.act(action, args, function (done, err) {
            if (err) foot.errText = refusal.text(err, "island.quick.session.failed")
        })
    }

    Row {
        width: foot.width
        spacing: Theme.gap
        Button {
            visible: foot.sessionOk
            label: I18n.tr("island.quick.session.lock")
            onClicked: foot.act("session.lock", {})
        }
        Button {
            visible: foot.sessionOk
            label: foot.armed ? I18n.tr("frontend.session.confirm.suspend") : I18n.tr("island.quick.session.suspend")
            onClicked: {
                if (!foot.armed) { foot.armed = true; return }
                foot.armed = false
                foot.act("session.suspend", {confirm: true})
            }
        }
        Button {
            label: I18n.tr("island.quick.session.power_menu")
            onClicked: foot.act("session.menu", {})
        }
    }
    Text {
        visible: foot.errText !== ""
        width: foot.width
        wrapMode: Text.WordWrap
        color: Theme.error
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: foot.errText
    }
}
