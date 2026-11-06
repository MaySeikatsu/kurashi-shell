import QtQuick

// StillCopy (I298): a ShaderEffectSource drawn once and then left alone (Ma), for a mask or a picture's copy. A window's
// scene graph starts anew each time it is mapped, and a copy that is not live is not drawn again by itself: it comes back
// empty, so what it masks is gone from the next reveal on; a window that never unmaps does not show it. Its owner still
// calls scheduleUpdate() when the content changes.
ShaderEffectSource {
    id: copy
    live: false
    Connections {
        target: copy.Window.window
        function onVisibleChanged() {
            if (copy.Window.window.visible) copy.scheduleUpdate()
        }
    }
}
