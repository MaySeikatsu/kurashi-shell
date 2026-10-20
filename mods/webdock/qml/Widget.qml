import QtQuick
import Quickshell
import qs.core
import qs.components

// Bar widget of the web dock (`widget:webdock`, docs/ux/webdock.md "Keyboard and a11y"): one button that shows or hides
// the dock on the output this bar is on (`webdock.toggle {output}`). Its drawing is the dock's edge: an outline with the
// strip bar in it, lit while the dock is open, and a dot while the dock is kept open. Its name says the same in words.
// Visible = subscribed (Ma): a hidden bar holds no document.
Item {
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n
    id: w
    // A side bar hands this over: the same glyph, in the bar's 36 px.
    property bool vertical: false

    property bool live: visible
    Watch { doc: "mod.webdock"; active: w.live }

    readonly property var d: Store.docs["mod.webdock"] || ({})
    readonly property bool loaded: Store.docs["mod.webdock"] !== undefined
    readonly property bool available: d.available !== false
    readonly property bool open: (d.mode || "hidden") !== "hidden"
    readonly property bool pinned: d.pinned === true
    // The bar's window (Quickshell's QsWindow attached object) names the output the bar is on.
    readonly property string outName: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.name : ""

    readonly property string stateWords: [
        open ? I18n.tr("webdock.dock.widget.open") : I18n.tr("webdock.dock.widget.closed"),
        pinned ? I18n.tr("webdock.dock.widget.pinned") : ""
    ].filter(function (s) { return s !== "" }).join(", ")

    function toggle() {
        if (available) Store.act("webdock.toggle", outName !== "" ? { output: outName } : {})
    }

    implicitWidth: w.vertical ? Theme.barH : Theme.controlH
    implicitHeight: w.vertical ? Theme.barH : Theme.controlH
    opacity: available ? 1 : Theme.staleOpacity
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: available ? I18n.tr("webdock.dock.widget") + ", " + stateWords : I18n.tr("webdock.dock.unavailable")

    Keys.onReturnPressed: w.toggle()
    Keys.onEnterPressed: w.toggle()
    Keys.onSpacePressed: w.toggle()

    Rectangle {
        id: frameR
        anchors.centerIn: parent
        width: 16
        height: 16
        radius: 4
        color: "transparent"
        border.width: 1.5
        border.color: Theme.fg
    }
    Rectangle {
        anchors.left: frameR.left
        anchors.top: frameR.top
        anchors.bottom: frameR.bottom
        anchors.margins: 3
        width: 4
        radius: 1
        color: w.open ? Theme.accent : Theme.dim
    }
    Rectangle {
        visible: w.pinned
        width: 5
        height: 5
        radius: 3
        color: Theme.accent
        anchors.right: frameR.right
        anchors.top: frameR.top
        anchors.rightMargin: -2
        anchors.topMargin: -2
    }

    FocusRing {
        anchors.fill: parent
        shown: w.activeFocus
        corner: Theme.rSm
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: w.toggle()
    }
}
