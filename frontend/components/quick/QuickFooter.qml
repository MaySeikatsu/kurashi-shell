import QtQuick
import "../../core"
import "../expanded"
import ".."

// The session footer (docs/ux/quick-settings.md, Design 4). Lock and suspend act only while the session service answers
// (svc.session `available`, the capability the daemon serves); without it they stay, inert, and the footer says why
// (I204, rule 2: they were hidden). Lock runs at once; suspend needs a second press within 3 s,
// as the session menu does (the daemon refuses it without `confirm`). The power menu is the existing session panel. There
// is no settings button yet: the brief's footer lists one, and `settings.open` (PROTOCOL §6) is there to build it on.
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
            enabled: foot.sessionOk
            label: I18n.tr("island.quick.session.lock")
            onClicked: foot.act("session.lock", {})
        }
        Button {
            enabled: foot.sessionOk
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
    Label {
        visible: !foot.sessionOk
        width: foot.width
        wrapMode: Text.WordWrap
        dim: true
        font.pixelSize: Theme.fsCaption
        text: I18n.tr("frontend.session.unavailable")
    }
    Label {
        visible: foot.errText !== ""
        width: foot.width
        wrapMode: Text.WordWrap
        color: Theme.error
        font.pixelSize: Theme.fsCaption
        text: foot.errText
    }
}
