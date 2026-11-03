import QtQuick
import "../../core"
import "../../core/motion"
import ".."

// A motion profile's thumbnail in the gallery (W59.6b; brief §8 item 2, §11): a panel card hanging from a strip of bar,
// drawn by the shell's own FormHost and forms. At rest it is a still — the frame at p = 0.5 of the panel's opening, grabbed
// once into an image (no layer, no Driver kept: Ma) and made again when the theme changes; while `active` (the card is
// hovered or focused) the opening plays once on the profile's curve, then the still is back. Under reduce motion it does
// not play. `form` and `curves` are the profile's: empty / null = the ones in effect (the gallery knows no other pack's
// until the daemon publishes them, CONTRACT-CHANGE row 625).
Item {
    id: th
    property string form: ""
    property var curves: null
    property bool active: false
    property string name: ""
    implicitWidth: 152
    implicitHeight: 52
    Accessible.role: Accessible.Animation
    Accessible.name: I18n.fmt("motion.ui.preview.thumb", { name: th.name })

    readonly property bool reduce: { Store.config; return Store.valueOf("a11y.reduce_motion", "") === true }
    readonly property bool shown: !!th.Window.window && th.Window.window.visible
    property bool playing: false
    onActiveChanged: if (active && !th.reduce && th.shown) th.playing = true
    // The still is made again after the theme (colours, forms, curves) changes, once.
    property bool stale: true
    Connections {
        target: Theme
        function onTokensChanged() { th.stale = true }
    }

    Image {
        id: still
        anchors.fill: parent
        visible: !th.playing && source != ""
        cache: false
    }

    // A frame: the bar's strip with the card under it at progress p (a Driver's while playing).
    component Frame: Item {
        id: fr
        property real p: 0.5
        width: th.width
        height: th.height
        clip: true
        Rectangle { z: 1; width: parent.width; height: 6; color: Theme.surface }
        FormHost {
            id: h
            x: Math.round(parent.width * 0.18)
            y: 6
            width: Math.round(parent.width * 0.64)
            height: parent.height - 10
            surface: "panel"
            edge: "top"
            origin: Qt.rect(width / 2 - 12, -6, 24, 6)
            progress: fr.p
            visible: fr.p > 0
            // A pack's own form (not the one in effect) is latched over the one FormHost takes from the tokens.
            function own() { if (th.form !== "" && busy) { latchedDir = "open"; latchedForm = th.form } }
            onBusyChanged: own()
            Component.onCompleted: own()
            SampleCard { anchors.fill: parent; surface: "panel"; thin: false; progress: fr.p; content: "with" }
        }
    }

    // Grabbing the still: the frame at 0.5, two frames on screen (a sheet form captures its card first), then an image.
    Loader {
        id: maker
        active: th.stale && th.shown && !th.playing && th.width > 0
        sourceComponent: Frame { p: 0.5 }
        property int frames: 0
        onActiveChanged: frames = 0
    }
    Connections {
        target: maker.active ? th.Window.window : null
        function onFrameSwapped() {
            if (++maker.frames < 2) { th.Window.window.requestUpdate(); return }
            if (maker.frames !== 2 || !maker.item) return
            maker.item.grabToImage(function (r) {
                still.source = r.url
                th.stale = false
            })
        }
    }

    // Playing once: the opening on the profile's curve, then back to the still.
    Loader {
        id: live
        active: th.playing
        sourceComponent: Item {
            width: th.width
            height: th.height
            Frame { p: drv.value }
            Driver {
                id: drv
                curves: th.curves || Theme.motionCurves
                onLanded: th.playing = false
                // (after the Driver has taken its rest at 0; a curve that cuts lands without a signal)
                Component.onCompleted: Qt.callLater(function () { drv.to = 1; if (!drv.running) th.playing = false })
            }
        }
    }
}
