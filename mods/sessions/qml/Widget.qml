import QtQuick
import Quickshell
import qs.core
import qs.components

// The sessions' bar module (`widget:sessions`; docs/ux/sessions.md "Glances"): the current project's name — the last
// one opened through the shell — beside its symbol; the symbol alone on a side bar or when the bar is short of room.
// Without noren the symbol is dimmed and its name says why. A click (or Enter on its tab stop) opens the card with the
// sessions (`panel:sessions`); hovering opens it through the shell's hover machinery, as every module's. Visible =
// subscribed (Ma).
Item {
    id: w
    required property var store
    required property var theme
    required property var i18n
    property bool vertical: false
    // The bar's fit (docs/ux/bar-fit.md): the name shrinks to `minWidth`, compact is the symbol alone.
    property bool compact: false
    property real room: 100000
    readonly property real fullWidth: label.text !== "" ? Theme.barH + Math.min(180, label.implicitWidth) + Theme.gap : Theme.barH
    readonly property real compactWidth: Theme.barH
    readonly property bool elastic: label.text !== ""
    readonly property real minWidth: Theme.barH

    property bool live: visible
    Watch { doc: "mod.sessions"; active: w.live }
    readonly property var d: Store.docs["mod.sessions"] || ({})
    readonly property bool missing: !!(d.noren && d.noren.state === "missing")
    readonly property string current: d.current ? String(d.current.name || "") : ""
    readonly property bool iconOnly: vertical || compact

    implicitWidth: iconOnly ? Theme.barH : Math.max(compactWidth, Math.min(room, fullWidth))
    implicitHeight: Theme.barH
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: missing ? I18n.tr("sessions.widget.missing")
        : (current !== "" ? I18n.tr("sessions.widget").replace("{name}", current) : I18n.tr("sessions.widget.none"))

    function openCard() { Store.act("mod.panel.open", { id: "sessions", panel: "sessions" }) }
    Keys.onReturnPressed: openCard()
    Keys.onEnterPressed: openCard()

    Icon {
        x: (Theme.barH - width) / 2
        y: (Theme.barH - height) / 2
        name: "work"
        glyph: "▣"
        color: w.missing ? Theme.dim : Theme.fg
        opacity: w.missing ? 0.6 : 1
    }
    Text {
        id: label
        visible: !w.iconOnly && text !== ""
        x: Theme.barH
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, w.width - Theme.barH - Theme.gap)
        elide: Text.ElideRight
        text: w.missing ? "" : w.current
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.tok("font.family", "sans-serif")
    }
    FocusRing { anchors.fill: parent; shown: w.activeFocus; corner: Theme.rSm }
}
