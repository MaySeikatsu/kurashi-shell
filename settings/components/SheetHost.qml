import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../core"

// Settings as a sheet (K63, docs/ux/settings.md "Settings as a sheet"): a layer surface over the whole focused output —
// a backdrop dimmed with the scrim, the sheet centred on it (1040 × 740, or 90 % of a smaller output) in the shell's
// radius, outline and shadow. The app's one content item is put into `slot` (shell.qml); this file knows nothing of
// pages. The output is the compositor's focused one as the daemon reports it (`svc.workspaces`, the workspace marked
// focused — the launcher's rule), read once when the sheet maps: the sheet does not follow the focus once open. Esc that
// no control takes, a click on the backdrop and the header's close button all ask `closeRequested`; the process ends
// after the sheet has faded out (`dismissed`).
PanelWindow {
    id: sh
    // Where the content goes (shell.qml reparents it here).
    readonly property alias slot: slot
    // The sheet's rectangle on the surface (the settings test checks it is centred).
    readonly property alias frame: frame
    // 0 → 1 while opening, back to 0 while closing; nothing animates in between (Ma).
    property real p: 0
    property bool closing: false
    signal dismissed()

    function focusedScreen() {
        var o = (Store.workspaces && Store.workspaces.outputs) || {}
        var s = Quickshell.screens
        for (var i = 0; i < s.length; i++) {
            var l = o[s[i].name] || []
            for (var j = 0; j < l.length; j++)
                if (l[j].focused) return s[i]
        }
        return s.length > 0 ? s[0] : null
    }
    // Latched: the binding is replaced by its first value once the sheet exists.
    property var pinned: focusedScreen()
    Component.onCompleted: pinned = pinned

    function close() {
        if (closing) return
        closing = true
        anim.stop()
        anim.from = p
        anim.to = 0
        anim.start()
    }

    screen: pinned
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "kurashi-settings"
    color: "transparent"

    // The fade starts on the first frame shown, so it is never half over before the surface is on screen.
    property bool gate: true
    Connections {
        target: frame.Window.window
        function onFrameSwapped() {
            if (!sh.gate) return
            sh.gate = false
            anim.from = sh.p
            anim.to = 1
            anim.start()
        }
    }
    NumberAnimation {
        id: anim
        target: sh
        property: "p"
        duration: Theme.stdMs
        easing.type: Easing.OutCubic
        onFinished: if (sh.closing && sh.p <= 0) sh.dismissed()
    }

    // The backdrop: the scrim over the desktop. A click on it closes; it takes no focus (UX brief, a11y).
    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: sh.p
        MouseArea {
            objectName: "sheet-backdrop"
            anchors.fill: parent
            onClicked: sh.close()
        }
    }

    Item {
        id: frame
        readonly property real inset: Theme.outlineW
        width: Math.round(Math.min(1040, sh.width * 0.9))
        height: Math.round(Math.min(740, sh.height * 0.9))
        x: Math.round((sh.width - width) / 2)
        y: Math.round((sh.height - height) / 2)
        opacity: Math.min(1, sh.p * 1.4)
        scale: 0.97 + 0.03 * sh.p
        Accessible.role: Accessible.Dialog
        Accessible.name: I18n.tr("settings.ui.title")

        // A click on the sheet never reaches the backdrop.
        MouseArea { anchors.fill: parent }
        // Shadows from the chrome: keycap's hard one straight down, soft's blurred one; flat has none.
        Rectangle {
            visible: Theme.shadowDy > 0
            y: Theme.shadowDy
            width: frame.width
            height: frame.height
            radius: Theme.rLg + 4
            color: Theme.line
        }
        Loader {
            anchors.fill: parent
            active: Theme.softR > 0
            sourceComponent: RectangularShadow {
                offset.y: Theme.softDy
                blur: Theme.softR
                spread: -1
                radius: Theme.rLg + 4
                color: Theme.softColor
            }
        }
        // The content, clipped to the sheet's corners (one static layer: no frame while still).
        ClippingRectangle {
            anchors.fill: parent
            radius: Theme.rLg + 4
            color: Theme.surface
            Item {
                id: slot
                anchors.fill: parent
            }
        }
        // The outline over the content's edge: the chrome's ink, else a hairline that keeps the sheet off the scrim.
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: Theme.rLg + 4
            border.width: Theme.outlineW > 0 ? Theme.outlineW : 1
            border.color: Theme.outlineW > 0 ? Theme.line : Theme.outline
        }
    }
}
