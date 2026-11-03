import QtQuick
import "../../core"
import ".."
import "../island"
import "../decor"
import Quickshell
import "../../surfaces" as S
import QtQuick.Effects

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
    // I374 (`launcher.button_logo`): the look's mark (default), the OS's logo (the daemon's `os.logo` token, from
    // os-release, tinted as the look says: `[decor] start.logo_tint`), or the user's own image (`launcher.button_icon`),
    // in every look. An image that does not load falls back to the mark; the log says why.
    S.BarConfig { id: cfg; screen: null }
    readonly property string logo: String(cfg.valueOf("launcher.button_logo", "look"))
    readonly property string ownPath: {
        var p = String(cfg.valueOf("launcher.button_icon", "") || "")
        if (p.indexOf("~/") === 0) p = String(Quickshell.env("HOME") || "") + p.substring(1)
        return p
    }
    readonly property string logoSource: {
        if (logo === "own" && ownPath !== "") return "file://" + ownPath
        var name = String(Theme.tok("os.logo", "") || "")
        if (logo === "os" && name !== "") return Quickshell.iconPath(name, true)
        return ""
    }
    readonly property string tint: logo === "os" ? String(Theme.decor("start.logo_tint", "none")) : "none"
    readonly property bool owned: logoSource !== "" && ownImg.status === Image.Ready
    readonly property Item face: owned ? own : (dressed ? dress : plain)
    width: face.width
    height: face.height
    slotHeights: [thickness]
    a11yName: I18n.tr("layout.module.launcher")
    function activate() { Store.act("launcher.toggle") }
    function geo() { return [["launcher", m]] }
    AnchorReport { target: m; key: "start"; output: m.output; enabled: m.anchored }

    Item {
        id: own
        visible: m.owned
        readonly property int h: Math.max(16, Math.round(m.thickness))
        width: h
        height: h
        anchors.verticalCenter: m.vertical ? undefined : parent.verticalCenter
        anchors.horizontalCenter: m.vertical ? parent.horizontalCenter : undefined
        Rectangle {
            anchors.centerIn: parent
            width: Math.round(own.h * 0.9)
            height: width
            radius: width / 2
            visible: m.open || ownHit.containsMouse || ownHit.pressed
            color: Qt.alpha(Theme.fg, m.open || ownHit.pressed ? 0.16 : 0.08)
        }
        Image {
            id: ownImg
            anchors.centerIn: parent
            width: Math.round(own.h * 0.7)
            height: width
            source: m.logoSource
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            fillMode: Image.PreserveAspectFit
            smooth: true
            // Synchronous: a small icon, and the tint's mask layer is made from it once it has loaded.
            // Drawn as is, or as the mask of its tint below (then hidden here, kept as a layer for the mask).
            visible: m.tint === "none"
            // Always layered (a 22 px icon): a layer switched on later, on an item already hidden, never renders.
            layer.enabled: true
            onStatusChanged: if (status === Image.Error) console.warn("launcher: the button logo " + source + " did not load; the look's mark stays")
        }
        // The tint: the logo's alpha over the text's ink, or over a conic sweep of the four console colours.
        Item {
            id: tintFill
            anchors.fill: ownImg
            visible: false
            layer.enabled: true
            Rectangle { anchors.fill: parent; visible: m.tint === "ink"; color: Theme.fg }
            // Four hard quarters (top left red, top right yellow, bottom right teal, bottom left blue), as the
            // console's four colours stand apart; plain rectangles (a Shape's gradient draws nothing in a bar window).
            Repeater {
                model: m.tint === "console" ? [["#e03a3e", 0, 0], ["#f2c230", 1, 0], ["#1fa59a", 1, 1], ["#3d7ec2", 0, 1]] : []
                Rectangle {
                    required property var modelData
                    x: modelData[1] * Math.ceil(tintFill.width / 2)
                    y: modelData[2] * Math.ceil(tintFill.height / 2)
                    width: Math.ceil(tintFill.width / 2)
                    height: Math.ceil(tintFill.height / 2)
                    color: modelData[0]
                }
            }
        }
        MultiEffect {
            anchors.fill: ownImg
            visible: m.tint !== "none" && m.owned
            source: tintFill
            maskEnabled: true
            maskSource: ownImg
        }
        MouseArea {
            id: ownHit
            anchors.fill: parent
            enabled: m.owned
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: m.activate()
        }
    }
    StartHost {
        id: dress
        visible: !m.owned
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
        visible: !m.dressed && !m.owned
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
