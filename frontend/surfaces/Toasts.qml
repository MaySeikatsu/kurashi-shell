import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"

// Toast stack (top right, focused output) plus the notification center, so shell.qml needs a
// single line. Expiry is daemon-side: a toast exists exactly while its id is in `toasts`.
// Like Stage the layer surface stays mapped but transparent/input-less when empty (K16, Ma).
Scope {
    id: root
    property var screen: null       // set by shell.qml: the focused output

    Watch { doc: "svc.notifications" }
    readonly property var doc: Store.docs["svc.notifications"] || ({})
    readonly property int maxToasts: 3
    readonly property bool centerOpen: (Store.docs["runtime.ui"] && Store.docs["runtime.ui"].panel) === "notifications"

    // Toast cards, newest first, from the ids the daemon says are showing.
    readonly property var shownItems: {
        var ids = doc.toasts || [], items = doc.items || [], out = []
        if (centerOpen) return out   // the center shows them; no duplicate stack
        for (var i = 0; i < items.length; i++)
            if (ids.indexOf(items[i].id) >= 0) out.push(items[i])
        out.sort(function (a, b) { return b.time - a.time })
        return out
    }
    readonly property int count: shownItems.length
    readonly property var visibleItems: shownItems.slice(0, maxToasts)
    readonly property int extra: Math.max(0, count - maxToasts)

    // Latched while toasts are up so the stack never jumps outputs mid-notification.
    property var latched: screen
    property int prevCount: 0
    onCountChanged: {
        if (count > 0 && prevCount === 0) latched = screen
        prevCount = count
    }

    NotificationCenter { screen: root.screen }

    PanelWindow {
        id: win
        screen: root.latched
        property real p: 0
        property bool gate: false
        property bool shown: false
        visible: shown     // unmapped at idle: mapped-surface budget (docs/BENCH.md)
        readonly property int slide: 16

        // Clears this output's bar: below a top bar, above a bottom one, left of a right one.
        BarConfig { id: bars; screen: win.screen }
        anchors { top: !bars.atBottom; bottom: bars.atBottom; right: true }
        margins { top: bars.topInset; bottom: bars.bottomInset; right: bars.rightInset }
        implicitWidth: stack.width + Theme.shadowDy
        implicitHeight: Math.max(1, stack.height + Theme.shadowDy)
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "kurashi-toasts"
        color: "transparent"
        mask: shown ? stackRegion : emptyRegion
        BackgroundEffect.blurRegion: shown ? stackRegion : emptyRegion
        Region { id: stackRegion; item: stack }
        Region { id: emptyRegion }

        Connections {
            target: root
            function onCountChanged() {
                if (root.count > 0) {
                    anim.stop()
                    if (!win.shown) { win.p = 0; win.gate = true; win.shown = true }
                    else { anim.from = win.p; anim.to = 1; anim.start() }
                } else if (win.shown) {
                    win.gate = false
                    anim.stop(); anim.from = win.p; anim.to = 0; anim.start()
                }
            }
        }
        NumberAnimation {
            id: anim
            target: win
            property: "p"
            duration: Theme.stdMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.enterCurve
            onFinished: if (win.p <= 0 && root.count === 0) win.shown = false
        }
        // Reveal starts on the first presented frame, not on mapping.
        Connections {
            target: stack.Window.window
            function onFrameSwapped() {
                if (win.gate) { win.gate = false; anim.from = win.p; anim.to = 1; anim.start() }
            }
        }

        Column {
            id: stack
            visible: win.shown
            spacing: Theme.gap
            // Slide in from the right edge; no group opacity (K16).
            x: win.slide * (1 - win.p)
            width: 340
            Repeater {
                model: root.visibleItems
                delegate: NotificationCard {
                    required property var modelData
                    item: modelData
                    onDismissed: Store.act("notify.dismiss", { id: item.id })
                    onInvoked: key => Store.act("notify.invoke", { id: item.id, key: key })
                }
            }
            Chip {
                visible: root.extra > 0
                anchors.right: parent.right
                text: "+" + root.extra
            }
        }
    }
}
