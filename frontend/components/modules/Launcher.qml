import QtQuick
import "../../core"
import ".."
import "../island"
import "../decor"
import Quickshell
import "../../surfaces" as S

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
    // The logo's colour (`launcher.logo_tint`, session 26): the look's (its `[decor] start.logo_tint` on the OS logo), the
    // picture as it is, the text's colour, or the palette's colours as sectors (the PS2 look's sweep) or tones.
    readonly property string tintChoice: String(cfg.valueOf("launcher.logo_tint", "look"))
    readonly property string tint: tintChoice === "look"
        ? (logo === "os" ? String(Theme.decor("start.logo_tint", "none")) : "none")
        : (tintChoice === "original" ? "none" : tintChoice)
    readonly property bool owned: logoSource !== "" && ownImg.status === Image.Ready
    readonly property Item face: owned ? own : (dressed ? dress : plain)
    width: face.width
    height: face.height
    slotHeights: [thickness]
    a11yName: I18n.tr("layout.module.launcher")
    function activate() {
        IslandGeom.noteOpener(m.output, IslandGeom.rectOf(m.output, "start") || IslandGeom.rectOf(m.output, "module:launcher"))
        Store.act("launcher.toggle")
    }
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
            // The tint (K110): one shader for every choice. The look's "console" is the four console colours as quarters
            // (top left red, top right yellow, bottom right teal, bottom left blue); the text's ink, the palette's
            // colours as quarters and its tones come from the theme. Session 27: the ink was a masked fill before and
            // drew nothing.
            layer.enabled: m.tint !== "none"
            layer.effect: logoTint
            onStatusChanged: if (status === Image.Error) console.warn("launcher: the button logo " + source + " did not load; the look's mark stays")
        }
        Component {
            id: logoTint
            IconTint {
                mode: m.tint === "console" ? "palette" : m.tint
                sectors: true
                colors: m.tint === "console" ? [Qt.color("#e03a3e"), Qt.color("#f2c230"), Qt.color("#1fa59a"), Qt.color("#3d7ec2")] : null
            }
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
