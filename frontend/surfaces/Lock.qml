import QtQuick
import Quickshell.Wayland
import "../core"
import "../components"
import "../components/lock"

// Session lock (ext-session-lock): the daemon owns the state (rule 1, runtime.lock); this only
// mirrors `locked`. The compositor shows one WlSessionLockSurface per output while locked and
// nothing exists while unlocked (Ma: 0 frames). Unlock happens solely when the daemon says
// locked=false; a lost daemon leaves the session locked.
// W53.0b (K80): each surface hosts the lock face the daemon names (`face`: the style's, or the plain one); the field
// stands on the focused output (`primary`), the others show the face's ground and clock where the face says so.
Item {
    id: root

    readonly property var st: Store.docs["runtime.lock"] || ({})
    readonly property bool locked: st.locked === true
    property double deadline: 0         // local wall-clock end of the retry delay
    property int remainingMs: 0

    Watch { doc: "runtime.lock" }
    Watch { doc: "svc.clock"; active: root.locked }
    Watch { doc: "svc.media"; active: root.locked }
    Watch { doc: "svc.workspaces"; active: root.locked }

    // The output with the focused workspace; "" when unknown (every surface then shows the field).
    readonly property string focusedOutput: {
        var outs = (Store.docs["svc.workspaces"] || {}).outputs || {}
        for (var name in outs) if (name !== "*")
            for (var i = 0; i < outs[name].length; i++)
                if (outs[name][i].focused) return name
        return ""
    }

    onStChanged: {
        deadline = st.retry_in_ms > 0 ? Date.now() + st.retry_in_ms : 0
        remainingMs = st.retry_in_ms > 0 ? st.retry_in_ms : 0
    }
    // Countdown only while locked and delayed, 1 Hz is enough for whole-second text.
    Timer {
        interval: 1000; repeat: true; running: root.locked && root.deadline > 0
        onTriggered: {
            var left = root.deadline - Date.now()
            if (left <= 0) { root.deadline = 0; root.remainingMs = 0 }
            else root.remainingMs = left
        }
    }

    WlSessionLock {
        locked: root.locked
        WlSessionLockSurface {
            id: surf
            color: Theme.surface
            // K59: this surface's tile set, shared by its reliefs, and the pointer light's sensor.
            property var tileSheet: tilesLoader.item
            Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
            LightSense {}
            FaceHost {
                anchors.fill: parent
                focus: true
                face: root.st.face || "plain"
                lock: root.st
                clock: Store.docs["svc.clock"] || ({})
                media: Store.docs["svc.media"] || ({})
                remainingMs: root.remainingMs
                primary: root.focusedOutput === "" || !surf.screen || surf.screen.name === root.focusedOutput
                onSubmitted: s => Store.send({ t: "intent", key: "lock.submit", value: s, coalesce: false })
                onCancelled: Store.send({ t: "intent", key: "lock.cancel", value: null, coalesce: false })
                onCapsKey: Store.send({ t: "intent", key: "lock.caps", value: null, coalesce: false })
            }
        }
    }
}
