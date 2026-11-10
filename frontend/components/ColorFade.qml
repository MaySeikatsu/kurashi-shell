import QtQuick
import "../core"

// The change of colour as a cross-fade (I472, K117 as amended in session 27): put one in a window, filling it. When the
// theme's colours change, ColorBlend asks every window for a picture of itself as it is (`Theme.fadeCapture`), then
// lets the new colours in (`Theme.fadeShow`): from that moment the window is drawn through a layer that mixes the
// picture with the window as it now is (shaders/color_mix.frag), from all picture to none (`Theme.fadeRun`). The shell
// is recoloured once and the fade is two textures mixed on the GPU: smooth however many colours change, and translucent
// parts (shadows) neither double nor flash, as they would with the picture drawn over the window. (The first version
// stepped every colour in JS: 60 to 110 ms a step on a real session — the user: "it looks very stuttery".) At rest
// there is no picture and no layer (Ma).
Item {
    id: f
    anchors.fill: parent
    z: 1000000
    property real t: 1
    readonly property Item host: parent
    // The picture of the window as it was. (Drawn at next to nothing rather than not at all: an item at opacity 0 is
    // left out of the scene, and its picture would never be taken.)
    ShaderEffectSource {
        id: was
        anchors.fill: parent
        recursive: true
        live: false
        hideSource: false
        sourceItem: null
        visible: sourceItem !== null
        opacity: 0.004
    }
    Component {
        id: mixer
        ShaderEffect {
            property var old: was
            property real t: f.t
            fragmentShader: Qt.resolvedUrl("../shaders/color_mix.frag.qsb")
        }
    }
    function done(): void {
        if (f.host) { f.host.layer.enabled = false; f.host.layer.effect = null }
        was.sourceItem = null
        f.t = 1
    }
    Connections {
        target: Theme
        function onFadeCaptureChanged() {
            if (!f.host || f.width < 1 || f.height < 1) return
            // (mid-fade: finish it; the picture is then of the window as it is)
            anim.stop()
            f.done()
            was.sourceItem = f.host
            was.scheduleUpdate()
        }
        function onFadeShowChanged() {
            if (was.sourceItem === null || !f.host) return
            f.t = 0
            f.host.layer.effect = mixer
            f.host.layer.enabled = true
        }
        function onFadeRunChanged() { if (was.sourceItem !== null) anim.restart() }
    }
    NumberAnimation {
        id: anim
        target: f
        property: "t"
        from: 0
        to: 1
        duration: Theme.fadeMs
        easing.type: Easing.InOutQuad
        onFinished: f.done()
    }
}
