import QtQuick
import qs.core
import qs.components
import qs.components.island

// A refused request said where the terminal's text cannot cover it (W85; docs/ux/terminal.md "Directories"): a folder that
// is not one (`notice` {key, path}: Shōjiki — never a silent `cd`). A strip in the error's tone laid over the place's tab
// row (the row stays where it is under it, the well and the terminal's size do not move): the symbol, the line, an action
// where one helps (the favourite's settings, when the folder is a favourite) and ×. It goes after 8 s, on ×, or when the
// next request succeeds (the daemon clears it); the place that shows the terminal puts it away (`terminal.dismiss`).
Item {
    id: ns
    property var doc: ({})
    // This place shows the terminal (only that one counts the strip's time and sends the dismissal).
    property bool owner: false
    readonly property var notice: doc.notice || null
    readonly property string path: notice ? String(notice.path || "") : ""
    readonly property bool favourite: {
        var f = (doc.settings && doc.settings.favourites) || []
        // (the notice names the expanded path; a favourite may be written with `~`)
        for (var i = 0; i < f.length; i++) {
            var fp = String(f[i].path || "")
            if (fp === path || (fp.indexOf("~") === 0 && path.endsWith(fp.substring(1)))) return true
        }
        return false
    }
    readonly property bool shown: notice !== null
    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.quickMs } }
    Accessible.role: Accessible.AlertMessage
    Accessible.name: line.text

    Timer {
        interval: 8000
        running: ns.shown && ns.owner && ns.visible
        onTriggered: Store.act("terminal.dismiss", {})
    }

    Block {
        id: strip
        anchors.fill: parent
        radius: Theme.rFull
        fill: Qt.tint(Theme.containerHigh, Qt.alpha(Theme.error, 0.18))
        flatBorder: Qt.alpha(Theme.error, 0.55)
        // (the strip takes the presses over the tab row under it)
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        Icon {
            id: sym
            x: Theme.pad
            anchors.verticalCenter: parent.verticalCenter
            name: "folder_off"
            glyph: "!"
            size: Theme.fs + 2
            color: Theme.error
        }
        Text {
            id: line
            x: sym.x + sym.width + Theme.gap
            width: Math.max(0, act.x - x - Theme.gap)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideMiddle
            text: ns.notice ? I18n.tr(String(ns.notice.key)).replace("{path}", ns.path) : ""
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
        }
        Row {
            id: act
            anchors.right: parent.right
            anchors.rightMargin: Theme.xs
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.xs
            KeyButton {
                visible: ns.favourite
                side: Math.max(20, strip.height - 6)
                label: I18n.tr("terminal.menu.edit_favourites")
                onClicked: { Store.act("settings.open", { page: "mod:terminal" }); Store.act("terminal.dismiss", {}) }
            }
            KeyButton {
                side: Math.max(20, strip.height - 6)
                icon: "close"
                glyph: "×"
                a11y: I18n.tr("terminal.notice.dismiss")
                onClicked: Store.act("terminal.dismiss", {})
            }
        }
    }
}
