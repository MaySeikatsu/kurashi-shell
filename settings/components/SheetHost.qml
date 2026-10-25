import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../core"

// Settings as a sheet (K63, docs/ux/settings.md "Settings as a sheet"): a layer surface over the whole focused output —
// a backdrop dimmed with the scrim, the sheet centred on it (1040 × 740, or 90 % of a smaller output) in the shell's
// radius, outline and shadow. The app's one content item is put into `slot` (shell.qml); this file knows nothing of
// pages. The output is the compositor's focused one as the daemon reports it (`svc.workspaces`, the workspace marked
// focused — the launcher's rule), read once when the sheet maps: the sheet does not follow the focus once open. Esc that
// no control takes, a click on the backdrop and the header's close button all close it (`close()`); the process ends
// after the sheet has faded out (`dismissed`). The material and light (K63, phase 2): the shell's own Relief (linked from
// frontend/), registered on the continuous sheet by this layer's place on the output, its tiles shared (`tileSheet`).
PanelWindow {
    id: sh
    // Where the content goes (shell.qml reparents it here).
    readonly property alias slot: slot
    // The sheet's rectangle on the surface (the settings test checks it is centred).
    readonly property alias frame: frame
    // 0 → 1 while opening, back to 0 while closing; nothing animates in between (Ma).
    property real p: 0
    property bool closing: false
    // The sheet's corners (the shell's large radius, a step rounder as the launcher's card).
    readonly property real radius: Theme.rLg + 4
    // The material (K63, K61): the sheet is a shell surface on the continuous sheet — its Reliefs register by this layer's
    // place on the output (all four anchors: its origin is the output's), all sampling this one tile set (Relief reads
    // `tileSheet` on its window). The pointer lamp and the spotlight's aim follow the pointer anywhere over the layer.
    property var tileSheet: sheetTiles.item
    Loader {
        id: sheetTiles
        active: Theme.texShell && Theme.texTilePx > 0
        sourceComponent: TileSheet {}
    }
    LightSense {}
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
        // Shadows from the chrome (K67, docs/ux/shadows.md): keycap's hard one along the shadow vector, soft's blurred one
        // offset along it (`softColor` carries the strength); flat and line have none (the vector is 0 there).
        Rectangle {
            visible: Theme.sinkX !== 0 || Theme.sinkY !== 0
            x: Theme.sinkX
            y: Theme.sinkY
            width: frame.width
            height: frame.height
            radius: sh.radius
            color: Theme.line
        }
        Loader {
            anchors.fill: parent
            active: Theme.softR > 0 && Theme.shadowAlpha > 0
            sourceComponent: RectangularShadow {
                offset.x: Theme.shadowX
                offset.y: Theme.shadowY
                blur: Theme.softR
                spread: -1
                radius: sh.radius
                color: Theme.softColor
            }
        }
        // The ground, then the content. Not a clipping layer: the relief registers by the window pixel it is drawn at, and an
        // offscreen layer would move it off the shell's sheet. The content rounds its own corners instead (`radius`, read by
        // shell.qml's header and sidebar), and the ground relief is the content's first child (shell.qml).
        Rectangle {
            anchors.fill: parent
            radius: sh.radius
            color: Theme.surface
        }
        Item {
            id: slot
            anchors.fill: parent
        }
        // The outline over the content's edge: the chrome's ink, else a hairline that keeps the sheet off the scrim.
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: sh.radius
            border.width: Theme.outlineW > 0 ? Theme.outlineW : 1
            border.color: Theme.outlineW > 0 ? Theme.line : Theme.outline
        }
    }
}
