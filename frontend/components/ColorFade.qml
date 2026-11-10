import QtQuick
import "../core"

// The change of colour as a cross-fade (I472, K117 as amended in session 27): put one in a window, filling it. When the
// theme's colours change, ColorBlend asks every window for a picture of itself as it is (`Theme.fadeCapture`), then lets
// the new colours in under that picture (`Theme.fadeShow`) and fades the picture away (`Theme.fadeRun`). The shell is
// recoloured once, under cover, and the fade itself is one texture's opacity on the GPU: smooth however many colours
// change. (The first version stepped every colour in JS: 60 to 110 ms a step on a real session, so a fade of 320 ms had
// three steps — the user: "it looks very stuttery".) At rest it holds no texture and draws nothing (Ma).
ShaderEffectSource {
    id: f
    anchors.fill: parent
    z: 1000000
    // (the window's own content, this item included: at opacity 0 it is not in its own picture)
    recursive: true
    live: false
    hideSource: false
    sourceItem: null
    visible: sourceItem !== null
    opacity: 0
    Connections {
        target: Theme
        function onFadeCaptureChanged() {
            anim.stop()
            // (mid-fade: the picture is what is on screen now, the fading one included)
            f.sourceItem = f.parent
            f.scheduleUpdate()
        }
        function onFadeShowChanged() { if (f.sourceItem !== null) f.opacity = 1 }
        function onFadeRunChanged() { if (f.sourceItem !== null) anim.restart() }
    }
    NumberAnimation {
        id: anim
        target: f
        property: "opacity"
        from: 1
        to: 0
        duration: Theme.fadeMs
        easing.type: Easing.InOutQuad
        onFinished: f.sourceItem = null
    }
}
