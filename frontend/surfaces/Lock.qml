import QtQuick
import Quickshell.Wayland
import "../core"
import "../components"

// Session lock (ext-session-lock): the daemon owns the state (rule 1, runtime.lock); this only
// mirrors `locked`. The compositor shows one WlSessionLockSurface per output while locked and
// nothing exists while unlocked (Ma: 0 frames). Unlock happens solely when the daemon says
// locked=false; a lost daemon leaves the session locked.
Item {
    id: root

    readonly property var st: Store.docs["runtime.lock"] || ({})
    readonly property bool locked: st.locked === true
    property double deadline: 0         // local wall-clock end of the retry delay
    property int remainingMs: 0

    Watch { doc: "runtime.lock" }
    Watch { doc: "svc.clock"; active: root.locked }
    Watch { doc: "svc.media"; active: root.locked }

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
            color: Theme.surface
            // K59: this surface's tile set, shared by its reliefs, and the pointer light's sensor.
            property var tileSheet: tilesLoader.item
            Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
            LightSense {}
            LockContent {
                anchors.fill: parent
                lock: root.st
                clock: Store.docs["svc.clock"] || ({})
                media: Store.docs["svc.media"] || ({})
                remainingMs: root.remainingMs
                onSubmitted: s => Store.send({ t: "intent", key: "lock.submit", value: s, coalesce: false })
                onCancelled: Store.send({ t: "intent", key: "lock.cancel", value: null, coalesce: false })
            }
        }
    }
}
