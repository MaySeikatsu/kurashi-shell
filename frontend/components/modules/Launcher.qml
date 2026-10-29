import QtQuick
import "../../core"
import ".."

// Module `launcher` (W53.0b, K80, docs/ux/styles.md "Decided" 10): a button that opens the launcher (`launcher.toggle`),
// lit while it is open. The style dresses it as its start button (`decor.start`: components/decor/start/<Name>.qml — the
// Windows styles' start button, the Macs' original menu mark; it gets `label`, `open`, `vertical`, `thickness` and says
// `clicked`); without a dress it is a plain icon button. A style never adds it: the module is in a bar only where the user
// (or a style's layout preset, "Also use its layout") put it (K45).
ModuleBase {
    id: m
    readonly property var ui: Store.docs["runtime.ui"] || ({})
    readonly property bool open: ui.launcher === true
    readonly property string dressFile: {
        var n = String(Theme.tok("decor.start", ""))
        return n === "" ? "" : n.split("-").map(function (w) { return w.charAt(0).toUpperCase() + w.slice(1) }).join("")
    }
    readonly property bool dressed: dress.status === Loader.Ready
    readonly property Item face: dressed ? dress.item : plain
    width: face.width
    height: face.height
    slotHeights: [thickness]
    a11yName: I18n.tr("layout.module.launcher")
    function activate() { Store.act("launcher.toggle") }
    function geo() { return [["launcher", m]] }

    Loader {
        id: dress
        active: m.dressFile !== ""
        source: active ? Qt.resolvedUrl("../decor/start/" + m.dressFile + ".qml") : ""
        onLoaded: {
            item.label = Qt.binding(function () { return I18n.tr("decor.start.label") })
            item.open = Qt.binding(function () { return m.open })
            item.vertical = Qt.binding(function () { return m.vertical })
            item.thickness = Qt.binding(function () { return m.thickness })
            item.clicked.connect(m.activate)
        }
    }
    IconButton {
        id: plain
        visible: !m.dressed
        anchors.verticalCenter: m.vertical ? undefined : parent.verticalCenter
        anchors.horizontalCenter: m.vertical ? parent.horizontalCenter : undefined
        icon: "apps"
        glyph: "⊞"
        lit: m.open
        // The host's tab stop presses it (Enter, Space): one stop, not two.
        activeFocusOnTab: false
        a11y: m.a11yName
        onClicked: m.activate()
    }
}
