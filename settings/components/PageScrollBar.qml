import QtQuick
import QtQuick.Controls.Basic
import "../core"

// A page's scrollbar (session 17, docs/ux/settings.md): on the right edge, only while the page is taller than its view;
// thin at rest, wider under the pointer, grab it to drag the page, a click on the track pages. Pointer-only (the
// keyboard scrolls the page itself).
ScrollBar {
    id: sb
    policy: ScrollBar.AsNeeded
    interactive: true
    minimumSize: 0.06
    readonly property bool wide: hovered || pressed
    padding: 2
    contentItem: Rectangle {
        implicitWidth: sb.wide ? 8 : 5
        radius: width / 2
        color: Qt.alpha(Theme.fg, sb.pressed ? 0.6 : sb.wide ? 0.5 : 0.35)
        opacity: sb.size < 1 ? 1 : 0
        Behavior on implicitWidth { enabled: Theme.springOn; NumberAnimation { duration: Theme.quickMs } }
    }
    background: Item { implicitWidth: 12 }
    Accessible.role: Accessible.ScrollBar
}
