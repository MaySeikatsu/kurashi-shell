import QtQuick
import "../../core"
import ".."
import "../expanded"

// Module `session` (W71 d, I475 8): the control centre's session row pinned to a bar — lock, suspend and the power menu,
// each a key as thick as the bar. Lock and suspend only while the session service answers (svc.session `available`);
// suspend needs a second press within 3 s, as the session row and the session menu do (the key says "Press again to
// suspend" in its name and draws in the error colour while armed); the power menu is the session panel. A refusal is the
// key's error colour and its accessible name. Compact (bar fit): the power menu's key alone; in a column the keys stack.
// Ma: the arming timer runs only while armed.
ModuleBase {
    id: m
    Watch { doc: "svc.session"; active: m.live }
    readonly property bool sessionOk: (Store.docs["svc.session"] || ({})).available === true
    property bool armed: false
    property string errText: ""
    Refusal { id: refusal }
    Timer { interval: 3000; running: m.armed; onTriggered: m.armed = false }
    function act(action, args) {
        m.errText = ""
        Store.act(action, args, function (done, err) { if (err) m.errText = refusal.text(err, "island.quick.session.failed") })
    }
    readonly property var keys: {
        var out = []
        if (sessionOk && !compact) {
            out.push({ id: "lock", icon: "lock", glyph: "🔒", name: I18n.tr("island.quick.session.lock") })
            out.push({ id: "suspend", icon: "bedtime", glyph: "☾",
                       name: I18n.tr(armed ? "frontend.session.confirm.suspend" : "island.quick.session.suspend") })
        }
        out.push({ id: "menu", icon: "power_settings_new", glyph: "⏻", name: I18n.tr("island.quick.session.power_menu") })
        return out
    }
    function press(id) {
        if (id === "lock") act("session.lock", {})
        else if (id === "suspend") {
            if (!armed) { armed = true; return }
            armed = false
            act("session.suspend", { confirm: true })
        } else act("session.menu", {})
    }
    readonly property int keyCount: keys.length
    fullW: vertical ? thickness : thickness * (sessionOk ? 3 : 1)
    compactW: vertical ? thickness : thickness
    width: vertical ? thickness : thickness * keyCount
    height: vertical ? thickness * keyCount : thickness
    slotHeights: vertical ? keys.map(function () { return m.thickness }) : [thickness]
    a11yName: errText !== "" ? errText : I18n.tr("layout.module.session")
    ownsFocus: true
    function activate() { press("menu") }
    function geo() { return [["session", m]] }

    Grid {
        columns: m.vertical ? 1 : m.keyCount
        Repeater {
            model: m.keys
            delegate: Item {
                id: key
                required property var modelData
                width: m.thickness
                height: m.thickness
                activeFocusOnTab: true
                Keys.onReturnPressed: m.press(modelData.id)
                Keys.onEnterPressed: m.press(modelData.id)
                Keys.onSpacePressed: m.press(modelData.id)
                Accessible.role: Accessible.Button
                Accessible.name: modelData.name
                readonly property bool warn: (modelData.id === "suspend" && m.armed) || (m.errText !== "" && modelData.id === "menu")
                Rectangle {
                    x: 3
                    y: 3
                    width: key.width - 6
                    height: key.height - 6
                    radius: Theme.rSm
                    color: tap.pressed || hov.hovered ? Theme.containerHigh : "transparent"
                }
                Icon {
                    anchors.centerIn: parent
                    name: key.modelData.icon
                    glyph: key.modelData.glyph
                    filled: true
                    color: key.warn ? Theme.error : Theme.fg
                }
                HoverHandler { id: hov }
                TapHandler { id: tap; acceptedButtons: Qt.LeftButton; onTapped: m.press(key.modelData.id) }
                FocusRing {
                    x: 3
                    y: 3
                    width: key.width - 6
                    height: key.height - 6
                    shown: key.activeFocus
                    corner: Theme.rSm
                }
            }
        }
    }
}
