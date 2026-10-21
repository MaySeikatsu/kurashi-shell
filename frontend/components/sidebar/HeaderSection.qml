import QtQuick
import Quickshell
import "../../core"
import ".."
import "../expanded"
import "../island"

// The right sidebar's `header` (docs/ux/sidebar.md; ii `sidebarRight/SidebarRightContent.qml` SystemButtonRow): the
// avatar key with the login name's letter, the name, and three keys — Settings (`settings.open`), Lock (`session.lock`,
// only while svc.session answers) and the session menu (`session.menu`, which opens on the Stage and so closes the
// sidebar). No uptime: no daemon value carries it yet (CONTRACT row 236), and the view polls nothing (rule 1).
Item {
    id: hd
    implicitHeight: Math.max(avatar.height, keys.implicitHeight)
    Watch { doc: "svc.session" }
    readonly property bool sessionOk: (Store.docs["svc.session"] || ({})).available === true
    readonly property string user: String(Quickshell.env("USER") || "")
    property string errText: ""
    Refusal { id: refusal }
    function act(action, args) {
        hd.errText = ""
        Store.act(action, args, function (done, err) { if (err) hd.errText = refusal.text(err, "sidebar.header.failed") })
    }

    Block {
        id: avatar
        width: 44
        height: 44 + Theme.shadowDy
        radius: Theme.rFull
        fill: Theme.selected
        Text {
            visible: hd.user !== ""
            anchors.centerIn: parent
            color: Theme.color("color.on_selected", Theme.fg)
            font.pixelSize: Theme.fsTitle + 4
            font.weight: Theme.wBold
            font.family: Theme.fam(text, Theme.families)
            text: hd.user.charAt(0).toUpperCase()
        }
        Icon {
            visible: hd.user === ""
            anchors.centerIn: parent
            name: "person"
            glyph: "◡"
            filled: true
            size: 24
            color: Theme.color("color.on_selected", Theme.fg)
        }
    }
    Column {
        x: avatar.width + Theme.gap + 2
        width: keys.x - x - Theme.gap
        anchors.verticalCenter: avatar.verticalCenter
        anchors.verticalCenterOffset: -Theme.shadowDy / 2
        Text {
            width: parent.width
            elide: Text.ElideRight
            color: Theme.fg
            font.pixelSize: Theme.fsTitle
            font.weight: Theme.wBold
            font.family: Theme.fam(text, Theme.families)
            text: hd.user !== "" ? hd.user : I18n.tr("sidebar.header.user")
        }
        Text {
            width: parent.width
            visible: text !== ""
            wrapMode: Text.WordWrap
            color: hd.errText !== "" ? Theme.error : Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: hd.errText
        }
    }
    Row {
        id: keys
        x: hd.width - width
        anchors.verticalCenter: avatar.verticalCenter
        spacing: Theme.xs
        KeyButton {
            icon: "settings"
            glyph: "⚙"
            side: 32
            a11y: I18n.tr("sidebar.header.settings")
            onClicked: hd.act("settings.open", {})
        }
        KeyButton {
            visible: hd.sessionOk
            icon: "lock"
            glyph: "⚿"
            side: 32
            a11y: I18n.tr("island.quick.session.lock")
            onClicked: hd.act("session.lock", {})
        }
        KeyButton {
            icon: "power_settings_new"
            glyph: "⏻"
            side: 32
            a11y: I18n.tr("island.quick.session.power_menu")
            onClicked: hd.act("session.menu", {})
        }
    }
}
