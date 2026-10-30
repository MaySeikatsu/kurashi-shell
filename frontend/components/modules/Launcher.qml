import QtQuick
import "../../core"
import ".."
import "../island"
import "../decor"

// Module `launcher` (W53.0b, K80, docs/ux/styles.md "Decided" 10): a button that opens the launcher (`launcher.toggle`),
// lit while it is open. The style dresses it as its start button (StartHost: `decor.start`, components/decor/start/
// <Name>.qml — the Windows styles' start button, the Macs' original menu mark; contract start/StartBase.qml: `label`,
// `pressed`, `open`, `vertical`); without a dress it is a plain icon button. The module owns the click: the dress only
// draws. A style never adds it: the module is in a bar only where the user (or a style's layout preset, "Also use its
// layout") put it (K45). It registers itself as the `start` origin (IslandGeom), where the start-menu skin hangs from.
ModuleBase {
    id: m
    readonly property var ui: Store.docs["runtime.ui"] || ({})
    readonly property bool open: ui.launcher === true
    readonly property bool dressed: dress.ready
    readonly property Item face: dressed ? dress : plain
    width: face.width
    height: face.height
    slotHeights: [thickness]
    a11yName: I18n.tr("layout.module.launcher")
    function activate() { Store.act("launcher.toggle") }
    function geo() { return [["launcher", m]] }
    AnchorReport { target: m; key: "start"; output: m.output; enabled: m.anchored }

    StartHost {
        id: dress
        anchors.verticalCenter: m.vertical ? undefined : parent.verticalCenter
        anchors.horizontalCenter: m.vertical ? parent.horizontalCenter : undefined
        open: m.open
        vertical: m.vertical
        pressed: hit.pressed
        onClicked: m.activate()
        MouseArea {
            id: hit
            anchors.fill: parent
            enabled: dress.ready
            cursorShape: Qt.PointingHandCursor
            onClicked: m.activate()
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
