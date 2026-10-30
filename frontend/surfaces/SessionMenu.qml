import QtQuick
import "../core"
import "../components"
import "../components/decor"

// Session menu (runtime.ui.panel === "session", opened by the `session.menu` action), shown inside
// the Stage card. A pure view: each entry sends one daemon action and nothing else. Lock runs at
// once; the others need a second press within 3 s, which sends {confirm: true} (the daemon refuses
// them without it). Keyboard: Up/Down or Tab move, Enter runs, Esc closes. On success the panel
// closes (ui.close); on failure the daemon's text is shown here.
Item {
    id: menu

    // Stage sets this while the menu is on screen. Leaving it disarms and clears the error: an arm
    // must not survive a close, or reopening the menu would make one press destructive.
    property bool active: false

    // Keys are spelled out so every string is greppable against i18n/ (rule 8).
    readonly property var entries: [
        { label: "action.session.lock", confirm: "", action: "session.lock", destructive: false, icon: "lock", glyph: "🔒" },
        { label: "action.session.suspend", confirm: "frontend.session.confirm.suspend", action: "session.suspend", destructive: true, icon: "bedtime", glyph: "☾" },
        { label: "action.session.logout", confirm: "frontend.session.confirm.logout", action: "session.logout", destructive: true, icon: "logout", glyph: "⇥" },
        { label: "action.session.reboot", confirm: "frontend.session.confirm.reboot", action: "session.reboot", destructive: true, icon: "restart_alt", glyph: "↻" },
        { label: "action.session.poweroff", confirm: "frontend.session.confirm.poweroff", action: "session.poweroff", destructive: true, icon: "power_settings_new", glyph: "⏻" }
    ]
    property int cursor: 0
    property int armed: -1      // entry index waiting for its confirming press
    property bool busy: false   // an action is in flight; presses are ignored until it answers
    property string errText: ""
    // The look's menu (W53, row 591): its corner and, where it names a menu part, the part as each key's face.
    MenuStyle { id: ms }

    // Five keys in a row (SekaiPop's power menu): icon over label, the armed one lit and asking to confirm.
    readonly property int keyW: 92
    implicitWidth: entries.length * keyW + (entries.length - 1) * Theme.gap
    implicitHeight: body.implicitHeight

    onActiveChanged: if (!active) { disarm(); errText = "" }

    // Runs only for the 3 s after a first press (Ma: nothing ticks while the menu is not armed).
    Timer {
        id: disarmTimer
        interval: 3000
        onTriggered: menu.armed = -1
    }
    function disarm() {
        disarmTimer.stop()
        armed = -1
    }

    function activate(i) {
        if (busy) return
        var e = entries[i]
        if (e.destructive && armed !== i) {
            errText = ""
            armed = i
            disarmTimer.restart()
            return
        }
        disarm()
        errText = ""
        busy = true
        Store.act(e.action, e.destructive ? { confirm: true } : {}, function (done, err) {
            busy = false
            if (err) errText = I18n.tr(err.msg || "") || I18n.tr("frontend.session.failed")
            else Store.act("ui.close")
        })
    }

    // Keys come from the Stage card, the Stage's one keyboard focus holder: a second holder here
    // would clear the card's focus flag for good. Returns false for keys the menu does not use.
    function handleKey(key) {
        var n = entries.length
        if (key === Qt.Key_Down || key === Qt.Key_Right || key === Qt.Key_Tab) cursor = (cursor + 1) % n
        else if (key === Qt.Key_Up || key === Qt.Key_Left || key === Qt.Key_Backtab) cursor = (cursor + n - 1) % n
        else if (key === Qt.Key_Return || key === Qt.Key_Enter) activate(cursor)
        else return false
        return true
    }

    Column {
        id: body
        width: menu.implicitWidth
        spacing: Theme.gap

        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            color: Theme.fg
            font.pixelSize: Theme.fsTitle
            font.weight: Theme.wBold
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("action.session.menu")
        }
        Row {
            spacing: Theme.gap
            Repeater {
                // Made only while the menu is on screen (B35): five hidden keys and their glyphs' fallback fonts cost ~7 MiB
                // PSS in the Stage at idle (W35 bench). The closing fold keeps them: the card stays visible until it is in.
                model: menu.visible ? menu.entries : []
                delegate: Block {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool lit: menu.cursor === index
                    readonly property bool isArmed: menu.armed === index
                    width: menu.keyW
                    height: 96 + Theme.shadowDy
                    radius: ms.radius(Theme.rLg)
                    pressed: tap.pressed
                    // An outlined chrome with no shadow (line): the keys are outlined boxes, no fill until lit.
                    fill: isArmed ? Theme.accent : (lit ? Theme.selected
                        : (Theme.outlineW > 0 && Theme.shadowDy <= 0 && Theme.softR <= 0 || ms.has ? "transparent" : Theme.containerHigh))
                    flatBorder: lit && !isArmed && !ms.has ? Theme.outline : "transparent"
                    Loader {
                        anchors.fill: parent
                        anchors.bottomMargin: Theme.shadowDy
                        active: ms.has
                        source: active ? ms.rowBackground : ""
                        onLoaded: item.highlighted = Qt.binding(function () { return row.lit || row.isArmed })
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.xs + 2
                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: row.modelData.icon
                            glyph: row.modelData.glyph
                            filled: row.lit || row.isArmed
                            size: 30
                            color: row.isArmed ? Theme.fgOnAccent : (row.lit ? ms.ink(Theme.fgOnSelected) : Theme.fg)
                            scale: row.lit ? 1.1 : 1
                            Behavior on scale {
                                enabled: menu.active && Theme.springOn
                                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot }
                            }
                        }
                        Text {
                            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                            antialiasing: !Theme.pixelType
                            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                            width: menu.keyW - 2 * Theme.gap
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            color: row.isArmed ? Theme.fgOnAccent : (row.lit ? ms.ink(Theme.fgOnSelected) : Theme.fg)
                            font.pixelSize: Theme.fsCaption + 1
                            font.weight: Theme.wMedium
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.tr(row.isArmed ? row.modelData.confirm : row.modelData.label)
                        }
                    }
                    HoverHandler { onHoveredChanged: if (hovered) menu.cursor = row.index }
                    TapHandler { id: tap; onTapped: menu.activate(row.index) }
                }
            }
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            width: body.width
            visible: menu.errText !== ""
            wrapMode: Text.WordWrap
            color: Theme.color("color.error", "#c9404b")
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: menu.errText
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            width: body.width
            color: Theme.dim
            font.pixelSize: Theme.fs - 2
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("frontend.session.hint")
        }
    }
}
