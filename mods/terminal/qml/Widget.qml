import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.components

// The terminal's bar module (`widget:terminal`; docs/ux/terminal.md "The bar module"). Three forms (`bar_mode`):
//   icon    a shell symbol, lit while the drop-down is out;
//   status  the symbol and the active tab's state: the program in the foreground, else the directory's last part;
//   input   a field: a click (or Enter on its tab stop) takes the keyboard, Enter runs the line in the terminal (`run_in`:
//           the current tab or a new one; `input_target`: show the drop-down, or run quietly), Up/Down walk the history,
//           Esc gives the keyboard back. The bar's own window takes no keyboard, so the field is a small layer window of its
//           own laid over the module while it is used (mapped on the click, gone on Enter or Esc: 0 frames otherwise).
// A hover or a click opens the terminal's card here (`panel:terminal`, through ModWidget: the shell's hover machinery);
// a middle click toggles the drop-down. Visible = subscribed (Ma).
Item {
    id: w
    required property var store
    required property var theme
    required property var i18n
    property bool vertical: false
    // The bar's fit (docs/ux/bar-fit.md): the field is elastic down to `minWidth`; compact is the symbol alone.
    property bool compact: false
    property real room: 100000
    readonly property real fullWidth: mode === "input" ? Theme.barH + 220 : (mode === "status" && statusText !== "" ? Theme.barH + Math.min(200, statusLabel.implicitWidth) + Theme.gap : Theme.barH)
    readonly property real compactWidth: Theme.barH
    readonly property bool elastic: mode !== "icon"
    readonly property real minWidth: mode === "input" ? Theme.barH + 120 : Theme.barH

    property bool live: visible
    Watch { doc: "mod.terminal"; active: w.live }
    readonly property var d: Store.docs["mod.terminal"] || ({})
    readonly property var s: d.settings || ({})
    readonly property string mode: vertical || compact ? "icon" : String(s.bar_mode || "icon")
    readonly property bool out: !!(d.dropdown && d.dropdown.open)
    readonly property var host: d.host || ({})
    readonly property bool broken: host.state === "missing" || host.state === "failed" || host.crashed === true
    readonly property string outName: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.name : ""
    readonly property var activeTab: {
        var t = d.tabs || []
        for (var i = 0; i < t.length; i++) if (t[i].id === d.active) return t[i]
        return null
    }
    function tail(p) { var parts = String(p || "").split("/").filter(function (x) { return x !== "" }); return parts.length ? parts[parts.length - 1] : "" }
    readonly property string statusText: !activeTab ? "" : (activeTab.program ? String(activeTab.program) : tail(activeTab.cwd || activeTab.dir))

    implicitWidth: Math.max(compactWidth, Math.min(room, fullWidth))
    implicitHeight: Theme.barH
    activeFocusOnTab: true
    Accessible.role: mode === "input" ? Accessible.EditableText : Accessible.Button
    Accessible.name: (broken ? I18n.tr("terminal.widget.broken") : I18n.tr("terminal.widget"))
        + (out ? ", " + I18n.tr("terminal.widget.out") : "")
        + (statusText !== "" ? ", " + statusText : "")

    function toggle() { Store.act("terminal.toggle", outName !== "" ? { output: outName } : {}) }
    // Enter on the tab stop: the field in input mode, else the card (as every module's key opens its card).
    Keys.onReturnPressed: mode === "input" ? field.open() : Store.act("mod.panel.open", { id: "terminal", panel: "terminal" })
    Keys.onEnterPressed: mode === "input" ? field.open() : Store.act("mod.panel.open", { id: "terminal", panel: "terminal" })

    Icon {
        id: glyph
        x: (Theme.barH - width) / 2
        y: (Theme.barH - height) / 2
        name: "terminal"
        glyph: "›_"
        filled: w.out
        color: w.broken ? Theme.error : (w.out ? Theme.accent : Theme.fg)
    }
    Text {
        id: statusLabel
        visible: w.mode === "status" && w.statusText !== ""
        x: Theme.barH
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, w.width - Theme.barH - Theme.gap)
        elide: Text.ElideRight
        text: w.statusText
        color: w.activeTab && w.activeTab.program ? Theme.fg : Theme.dim
        font.pixelSize: Theme.fs
        font.family: Theme.tok("font.family_mono", "monospace")
    }

    // The field's face in the bar (what the user sees before and after typing).
    Rectangle {
        id: face
        visible: w.mode === "input"
        x: Theme.barH
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, w.width - Theme.barH - Theme.xs)
        height: Theme.barH - 10
        radius: Theme.rSm
        color: Qt.alpha(Theme.fg, 0.08)
        border.width: 1
        border.color: field.visible ? Theme.accent : Qt.alpha(Theme.fg, 0.18)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: Theme.gap
            width: parent.width - 2 * Theme.gap
            elide: Text.ElideRight
            visible: !field.visible
            text: I18n.tr("terminal.input.placeholder").replace("{prefix}", String(w.s.run_prefix || "$"))
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.tok("font.family_mono", "monospace")
        }
    }

    // The field itself: a layer window over the face while it is used, so the keyboard can reach it.
    PanelWindow {
        id: field
        visible: false
        screen: QsWindow.window ? QsWindow.window.screen : null
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "kurashi-terminal-field"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors.top: true
        anchors.left: true
        property point at: Qt.point(0, 0)
        margins.left: at.x
        margins.top: at.y
        implicitWidth: Math.max(1, face.width)
        implicitHeight: Math.max(1, face.height)
        property int hist: -1
        function open() {
            if (w.mode !== "input" || !QsWindow.window) return
            var o = Light.originOf(QsWindow.window)
            var p = face.mapToItem(null, 0, 0)
            at = Qt.point(Math.round(o.x + p.x), Math.round(o.y + p.y))
            hist = -1
            input.text = ""
            visible = true
            input.forceActiveFocus()
        }
        function close() { visible = false }
        Rectangle {
            anchors.fill: parent
            radius: Theme.rSm
            color: Theme.surface
            border.width: 1
            border.color: Theme.accent
            TextInput {
                id: input
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.gap
                width: parent.width - 2 * Theme.gap
                clip: true
                color: Theme.fg
                selectionColor: Qt.alpha(Theme.accent, 0.4)
                font.pixelSize: Theme.fs
                font.family: Theme.tok("font.family_mono", "monospace")
                Accessible.role: Accessible.EditableText
                Accessible.name: I18n.tr("terminal.input.a11y")
                Keys.onReturnPressed: field.run()
                Keys.onEnterPressed: field.run()
                Keys.onEscapePressed: field.close()
                Keys.onUpPressed: field.walk(1)
                Keys.onDownPressed: field.walk(-1)
                onActiveFocusChanged: if (!activeFocus && field.visible) field.close()
            }
        }
        function walk(by) {
            var h = w.d.history || []
            if (h.length === 0) return
            hist = Math.max(-1, Math.min(h.length - 1, hist + by))
            input.text = hist < 0 ? "" : String(h[h.length - 1 - hist])
            input.cursorPosition = input.text.length
        }
        function run() {
            var t = input.text
            if (t.trim() === "") { close(); return }
            Store.act("terminal.run", { text: t, show: w.s.input_target !== "quiet", output: w.outName })
            close()
        }
    }

    FocusRing { anchors.fill: parent; shown: w.activeFocus; corner: Theme.rSm }
    // The field's click: its own (the card opens on a hover, or a click on the symbol).
    MouseArea {
        visible: w.mode === "input"
        x: face.x
        width: face.width
        height: parent.height
        cursorShape: Qt.IBeamCursor
        onClicked: field.open()
    }
    MouseArea {
        width: w.mode === "input" ? Theme.barH : parent.width
        height: parent.height
        acceptedButtons: Qt.MiddleButton
        onClicked: w.toggle()
    }
}
