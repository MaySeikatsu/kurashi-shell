import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"

// A shortcut row's control (K64, W35-keys), as GNOME's and KDE's shortcut fields: the combo as keycaps; a click, Enter or
// Space starts recording ("Press a key combination…"), the next key with its modifiers is the new combo, Esc cancels,
// Backspace removes the shortcut, Tab leaves. While it records, the compositor's own shortcuts are inhibited
// (zwp_keyboard_shortcuts_inhibit), so Super+Space reaches the field instead of opening the launcher; niri still runs the
// binds marked allow-inhibiting=false (session menu, lock). A key that types text needs a modifier (the daemon's rule,
// keys.rs `types_text`). A combo another action has asks first: Replace takes it from that action in one change (one
// undo step), Cancel keeps both. Under the field, what `svc.keys` says of the combo once written: left out (unknown key,
// taken), shared, or meeting a bind of the user's niri config. The daemon decides all of it; this only records and words.
Column {
    id: rec
    objectName: "recorder:" + rec.rowKey
    // Set by SettingRow (a picker knows its key).
    property string rowKey: ""
    // A reason's link to the row that has the combo (SettingRow connects it to its own).
    signal openKey(string key)
    spacing: Theme.gap / 2

    readonly property var row: { Store.schema; var h = Store.rowOf(rec.rowKey); return h ? h.row : ({}) }
    readonly property string label: rec.row.label ? I18n.tr(rec.row.label) : rec.rowKey
    readonly property var prov: { Store.config; return Store.prov(rec.rowKey, "") }
    readonly property string value: rec.prov && typeof rec.prov.value === "string" ? rec.prov.value : ""
    // Inert while keys.write is off or a forced layer (Nix) holds the value: the row's reason line says why.
    readonly property bool inert: !!rec.prov && (rec.prov.reason === "settings.inert.requires" || !!rec.prov.forced_by)
    readonly property bool editable: !rec.inert && Store.live

    // svc.keys, watched while a recorder shows (refcounted with the page's status; Ma).
    property bool held: false
    function hold(on) {
        if (on === held) return
        held = on
        if (on) Store.watch("svc.keys")
        else Store.unwatch("svc.keys")
    }
    onVisibleChanged: hold(visible)
    Component.onCompleted: hold(visible)
    Component.onDestruction: hold(false)
    readonly property var doc: Store.docs["svc.keys"]
    readonly property var binds: rec.doc && Array.isArray(rec.doc.binds) ? rec.doc.binds : []
    readonly property var bind: rec.binds.find(function (b) { return b.key === rec.rowKey }) ?? null
    readonly property bool writing: !!rec.doc && rec.doc.write === true

    // --- recording -----------------------------------------------------------------------------------
    property bool recording: false
    // Modifiers held right now, as keycaps while recording.
    property var heldMods: []
    // A line under the field while recording: a key that needs a modifier, or one without a name.
    property string notice: ""
    // A combo another action has: {combo, key, label}, asking Replace or Cancel.
    property var pending: null

    function start() {
        if (!rec.editable) return
        rec.pending = null
        rec.notice = ""
        rec.heldMods = []
        rec.recording = true
        field.forceActiveFocus()
    }
    function stop() {
        rec.recording = false
        rec.heldMods = []
        rec.notice = ""
    }
    function cancel() { rec.stop(); rec.pending = null }
    function commit(combo) {
        rec.stop()
        if (combo === rec.value) return
        var lc = combo.toLowerCase()
        var other = combo === "" ? null : rec.binds.find(function (b) {
            return b.key !== rec.rowKey && b.canon === lc
        })
        if (other) {
            rec.pending = { combo: combo, key: other.key, label: I18n.tr(Store.labelOf(other.key)) }
            Qt.callLater(function () { replaceKey.forceActiveFocus() })
            return
        }
        Store.setValue(rec.rowKey, combo, "")
    }
    function replace() {
        var p = rec.pending
        if (!p) return
        rec.pending = null
        Store.apply([{ set: rec.rowKey, value: p.combo }, { set: p.key, value: "" }])
        field.forceActiveFocus()
    }
    function keepBoth() { rec.pending = null; field.forceActiveFocus() }

    // Qt key → the xkb key name niri reads. With Shift held, a symbol is named by its unshifted key (US layout), as niri
    // matches binds on the key's own symbol (Mod+Shift+Slash, not Mod+Question).
    readonly property var names: ({
        [Qt.Key_Space]: "Space", [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "KP_Enter", [Qt.Key_Tab]: "Tab",
        [Qt.Key_Backtab]: "Tab", [Qt.Key_Backspace]: "BackSpace", [Qt.Key_Delete]: "Delete", [Qt.Key_Escape]: "Escape",
        [Qt.Key_Home]: "Home", [Qt.Key_End]: "End", [Qt.Key_PageUp]: "Page_Up", [Qt.Key_PageDown]: "Page_Down",
        [Qt.Key_Left]: "Left", [Qt.Key_Right]: "Right", [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down",
        [Qt.Key_Insert]: "Insert", [Qt.Key_Print]: "Print", [Qt.Key_Pause]: "Pause", [Qt.Key_ScrollLock]: "Scroll_Lock",
        [Qt.Key_Menu]: "Menu", [Qt.Key_Comma]: "Comma", [Qt.Key_Period]: "Period", [Qt.Key_Slash]: "Slash",
        [Qt.Key_Semicolon]: "Semicolon", [Qt.Key_Apostrophe]: "Apostrophe", [Qt.Key_BracketLeft]: "BracketLeft",
        [Qt.Key_BracketRight]: "BracketRight", [Qt.Key_Backslash]: "Backslash", [Qt.Key_Minus]: "Minus",
        [Qt.Key_Equal]: "Equal", [Qt.Key_QuoteLeft]: "Grave",
        [Qt.Key_Exclam]: "Exclam", [Qt.Key_At]: "At", [Qt.Key_NumberSign]: "NumberSign", [Qt.Key_Dollar]: "Dollar",
        [Qt.Key_Percent]: "Percent", [Qt.Key_AsciiCircum]: "AsciiCircum", [Qt.Key_Ampersand]: "Ampersand",
        [Qt.Key_Asterisk]: "Asterisk", [Qt.Key_ParenLeft]: "ParenLeft", [Qt.Key_ParenRight]: "ParenRight",
        [Qt.Key_Underscore]: "Underscore", [Qt.Key_Plus]: "Plus", [Qt.Key_BraceLeft]: "BraceLeft",
        [Qt.Key_BraceRight]: "BraceRight", [Qt.Key_Colon]: "Colon", [Qt.Key_QuoteDbl]: "QuoteDbl", [Qt.Key_Less]: "Less",
        [Qt.Key_Greater]: "Greater", [Qt.Key_Question]: "Question", [Qt.Key_Bar]: "Bar", [Qt.Key_AsciiTilde]: "AsciiTilde",
        [Qt.Key_VolumeUp]: "XF86AudioRaiseVolume", [Qt.Key_VolumeDown]: "XF86AudioLowerVolume",
        [Qt.Key_VolumeMute]: "XF86AudioMute", [Qt.Key_MicMute]: "XF86AudioMicMute", [Qt.Key_MediaPlay]: "XF86AudioPlay",
        [Qt.Key_MediaTogglePlayPause]: "XF86AudioPlay", [Qt.Key_MediaPause]: "XF86AudioPause",
        [Qt.Key_MediaStop]: "XF86AudioStop", [Qt.Key_MediaNext]: "XF86AudioNext", [Qt.Key_MediaPrevious]: "XF86AudioPrev",
        [Qt.Key_MonBrightnessUp]: "XF86MonBrightnessUp", [Qt.Key_MonBrightnessDown]: "XF86MonBrightnessDown",
        [Qt.Key_KeyboardBrightnessUp]: "XF86KbdBrightnessUp", [Qt.Key_KeyboardBrightnessDown]: "XF86KbdBrightnessDown",
        [Qt.Key_Calculator]: "XF86Calculator", [Qt.Key_LaunchMail]: "XF86Mail", [Qt.Key_HomePage]: "XF86HomePage",
        [Qt.Key_Search]: "XF86Search", [Qt.Key_Explorer]: "XF86Explorer", [Qt.Key_PowerOff]: "XF86PowerOff",
        [Qt.Key_Sleep]: "XF86Sleep", [Qt.Key_Suspend]: "XF86Suspend", [Qt.Key_WakeUp]: "XF86WakeUp",
        [Qt.Key_ScreenSaver]: "XF86ScreenSaver", [Qt.Key_Favorites]: "XF86Favorites", [Qt.Key_Tools]: "XF86Tools",
        [Qt.Key_TouchpadToggle]: "XF86TouchpadToggle", [Qt.Key_WLAN]: "XF86WLAN", [Qt.Key_Bluetooth]: "XF86Bluetooth",
        [Qt.Key_Display]: "XF86Display"
    })
    readonly property var unshifted: ({
        [Qt.Key_Exclam]: "1", [Qt.Key_At]: "2", [Qt.Key_NumberSign]: "3", [Qt.Key_Dollar]: "4", [Qt.Key_Percent]: "5",
        [Qt.Key_AsciiCircum]: "6", [Qt.Key_Ampersand]: "7", [Qt.Key_Asterisk]: "8", [Qt.Key_ParenLeft]: "9",
        [Qt.Key_ParenRight]: "0", [Qt.Key_Underscore]: "Minus", [Qt.Key_Plus]: "Equal", [Qt.Key_BraceLeft]: "BracketLeft",
        [Qt.Key_BraceRight]: "BracketRight", [Qt.Key_Colon]: "Semicolon", [Qt.Key_QuoteDbl]: "Apostrophe",
        [Qt.Key_Less]: "Comma", [Qt.Key_Greater]: "Period", [Qt.Key_Question]: "Slash", [Qt.Key_Bar]: "Backslash",
        [Qt.Key_AsciiTilde]: "Grave"
    })
    // Modifier keys: the modifier each one holds.
    readonly property var modKeys: ({
        [Qt.Key_Meta]: "Mod", [Qt.Key_Super_L]: "Mod", [Qt.Key_Super_R]: "Mod", [Qt.Key_Control]: "Ctrl",
        [Qt.Key_Alt]: "Alt", [Qt.Key_Shift]: "Shift", [Qt.Key_AltGr]: "", [Qt.Key_Hyper_L]: "", [Qt.Key_Hyper_R]: "",
        [Qt.Key_CapsLock]: "", [Qt.Key_NumLock]: ""
    })
    readonly property var modOrder: ["Mod", "Ctrl", "Alt", "Shift"]
    function modsOf(m) {
        var out = []
        if (m & Qt.MetaModifier) out.push("Mod")
        if (m & Qt.ControlModifier) out.push("Ctrl")
        if (m & Qt.AltModifier) out.push("Alt")
        if (m & Qt.ShiftModifier) out.push("Shift")
        return out
    }
    function keyName(event, shift) {
        var k = event.key
        if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode(k)
        if (k >= Qt.Key_0 && k <= Qt.Key_9) return String.fromCharCode(k)
        if (k >= Qt.Key_F1 && k <= Qt.Key_F35) return "F" + (k - Qt.Key_F1 + 1)
        if (shift && rec.unshifted[k] !== undefined) return rec.unshifted[k]
        return rec.names[k] ?? ""
    }
    // Keys that type text need a modifier; the others (F keys, media keys, Print, Home…) may stand alone (keys.rs).
    function alone(name) { return /^(F\d+|XF86\w+|Print|Pause|Scroll_Lock|Insert|Home|End|Page_Up|Page_Down|Menu)$/.test(name) }
    function capOf(part) { var k = "keys.cap." + part.toLowerCase(); return I18n.has(k) ? I18n.tr(k) : part }
    function spoken(combo) { return combo === "" ? I18n.tr("keys.recorder.none") : combo.split("+").map(rec.capOf).join("+") }

    function pressed(event) {
        if (!rec.recording) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                rec.start()
                event.accepted = true
            }
            return
        }
        event.accepted = true
        if (event.isAutoRepeat) return
        var mods = rec.modsOf(event.modifiers)
        if (rec.modKeys[event.key] !== undefined) {
            var m = rec.modKeys[event.key]
            if (m !== "" && mods.indexOf(m) < 0) mods.push(m)
            rec.heldMods = rec.modOrder.filter(function (x) { return mods.indexOf(x) >= 0 })
            return
        }
        // Bare Tab leaves the field (the keyboard is never trapped); bare Esc cancels; bare Backspace removes the shortcut.
        if (mods.length === 0 || (mods.length === 1 && mods[0] === "Shift" && event.key === Qt.Key_Backtab)) {
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) { rec.cancel(); event.accepted = false; return }
            if (event.key === Qt.Key_Escape) { rec.cancel(); return }
            if (event.key === Qt.Key_Backspace) { rec.commit(""); return }
        }
        var name = rec.keyName(event, mods.indexOf("Shift") >= 0)
        if (name === "") { rec.notice = I18n.tr("keys.recorder.unknown_key"); return }
        if (mods.length === 0 && !rec.alone(name)) {
            rec.notice = I18n.fmt("keys.recorder.needs_modifier", { key: rec.capOf(name) })
            return
        }
        rec.commit(mods.concat([name]).join("+"))
    }
    function released(event) {
        if (!rec.recording) return
        event.accepted = true
        var mods = rec.modsOf(event.modifiers)
        var m = rec.modKeys[event.key]
        if (m) mods = mods.filter(function (x) { return x !== m })
        rec.heldMods = rec.modOrder.filter(function (x) { return mods.indexOf(x) >= 0 })
    }

    // The compositor's shortcuts reach the field only while it records.
    ShortcutInhibitor {
        id: inhibitor
        window: rec.QsWindow.window
        enabled: rec.recording
    }
    readonly property bool inhibiting: inhibitor.active

    // --- the field -------------------------------------------------------------------------------------
    Rectangle {
        id: field
        objectName: "shortcut:" + rec.rowKey
        width: Math.min(rec.width, 360)
        implicitHeight: Theme.controlH
        radius: Theme.rSm
        color: rec.recording ? Theme.surface : Theme.containerHigh
        opacity: rec.editable ? 1 : 0.5
        border.width: rec.recording ? 2 : (rec.bind && rec.writing && (rec.bind.state === "invalid" || rec.bind.state === "conflict") ? 2 : 0)
        border.color: rec.recording ? Theme.accent : Theme.error
        activeFocusOnTab: rec.editable
        Keys.onPressed: event => rec.pressed(event)
        Keys.onReleased: event => rec.released(event)
        onActiveFocusChanged: if (!activeFocus && rec.recording) rec.cancel()
        Accessible.role: Accessible.Button
        Accessible.name: rec.recording ? I18n.fmt("keys.recorder.recording", { label: rec.label })
                                       : I18n.fmt("keys.recorder.name", { label: rec.label, combo: rec.spoken(rec.value) })
        Accessible.description: rec.recording ? I18n.tr("keys.recorder.hint") : I18n.tr("keys.recorder.help")

        Row {
            id: caps
            anchors.verticalCenter: parent.verticalCenter
            x: Theme.gap
            spacing: 4
            readonly property var parts: rec.recording ? rec.heldMods : (rec.value === "" ? [] : rec.value.split("+"))
            Repeater {
                model: caps.parts
                delegate: Rectangle {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    width: capText.implicitWidth + Theme.gap * 1.5
                    height: Theme.controlH - 10
                    radius: Theme.rSm - 2
                    color: Theme.container
                    border.width: 1
                    border.color: Theme.outline
                    Text {
                        id: capText
                        anchors.centerIn: parent
                        color: Theme.fg
                        font.pixelSize: Theme.fs - 1
                        font.weight: Theme.wMedium
                        font.family: Theme.fam(text, Theme.families)
                        text: rec.capOf(modelData)
                    }
                }
            }
            Text {
                visible: rec.recording || caps.parts.length === 0
                anchors.verticalCenter: parent.verticalCenter
                color: rec.recording ? Theme.fg : Theme.dim
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: rec.recording ? (rec.heldMods.length ? "+ …" : I18n.tr("keys.recorder.prompt")) : I18n.tr("keys.recorder.none")
            }
        }
        MouseArea {
            anchors.fill: parent
            enabled: rec.editable
            cursorShape: Qt.PointingHandCursor
            // Recording needs the keys: a click takes the focus (the one control that does), and a second click cancels.
            onClicked: rec.recording ? rec.cancel() : rec.start()
        }
        FocusRing {
            anchors.fill: parent
            shown: field.activeFocus && !rec.recording
            corner: field.radius
        }
    }

    // While recording: how to leave, or why the key was not taken.
    Text {
        visible: rec.recording
        width: rec.width
        wrapMode: Text.WordWrap
        color: rec.notice !== "" ? Theme.error : Theme.dim
        font.pixelSize: Theme.fs - 2
        font.family: Theme.fam(text, Theme.families)
        text: rec.notice !== "" ? "⊘ " + rec.notice : I18n.tr("keys.recorder.hint")
    }

    // Another action has the combo: Replace (one change: this row takes it, that one is cleared) or Cancel.
    Column {
        visible: rec.pending !== null
        width: rec.width
        spacing: Theme.gap / 2
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.fg
            font.pixelSize: Theme.fs - 2
            font.family: Theme.fam(text, Theme.families)
            text: rec.pending ? I18n.fmt("keys.recorder.taken", { combo: rec.spoken(rec.pending.combo), action: rec.pending.label }) : ""
        }
        Row {
            spacing: Theme.gap
            Button {
                id: replaceKey
                objectName: "keys-replace"
                primary: true
                label: I18n.tr("keys.recorder.replace")
                enabled: Store.live
                onClicked: rec.replace()
                Keys.onEscapePressed: event => { rec.keepBoth(); event.accepted = true }
            }
            Button {
                objectName: "keys-cancel"
                label: I18n.tr("keys.recorder.cancel")
                onClicked: rec.keepBoth()
                Keys.onEscapePressed: event => { rec.keepBoth(); event.accepted = true }
            }
        }
    }

    // What the daemon made of the combo, while it writes the file: left out, shared, or meeting the user's niri config.
    Repeater {
        model: {
            var b = rec.bind
            if (!b || !rec.writing || rec.recording || rec.pending) return []
            var out = []
            var label = function (k) { return I18n.tr(Store.labelOf(k)) }
            var combo = rec.spoken(b.combo || "")
            // The file is not ours to write (Home-Manager's, the user's), or not written at all: no combo here is in effect.
            if (["managed", "foreign", "unsupported", "error"].indexOf(rec.doc.state) >= 0 && b.state !== "none")
                return [{ error: false, key: "", text: I18n.tr("keys.not_written") }]
            if (b.state === "invalid")
                out.push({ error: true, text: I18n.tr(b.reason || "keys.invalid.key"), key: "" })
            else if (b.state === "conflict")
                out.push({ error: true, key: (b["with"] || [])[0] || "",
                           text: I18n.fmt("keys.conflict.taken", { combo: combo, action: label((b["with"] || [])[0] || "") }) })
            else if (b.state === "ok" && (b["with"] || []).length)
                out.push({ error: false, key: "", text: I18n.fmt("keys.conflict.shared", { actions: b["with"].map(label).join(", ") }) })
            if (b.config === "overridden")
                out.push({ error: true, key: "", text: I18n.fmt("keys.config.overridden", { combo: combo }) })
            else if (b.config === "replaces")
                out.push({ error: false, key: "", text: I18n.fmt("keys.config.replaces", { combo: combo }) })
            return out
        }
        delegate: Row {
            required property var modelData
            objectName: "keyline:" + rec.rowKey
            spacing: Theme.gap
            Text {
                width: Math.min(implicitWidth, rec.width - (link.visible ? link.width + Theme.gap : 0))
                wrapMode: Text.WordWrap
                color: modelData.error ? Theme.error : Theme.dim
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: (modelData.error ? "⊘ " : "") + modelData.text
            }
            LinkText {
                id: link
                visible: modelData.key !== ""
                text: I18n.tr("settings.ui.open")
                onActivated: rec.openKey(modelData.key)
            }
        }
    }
}
