import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"

// Notification center: content-sized overlay at the top right, shown while the daemon's
// runtime.ui.panel is "notifications" (opened by the island `notifications` face). Same
// permanently-mapped-but-input-less trick as Stage (K16); nothing is rendered while closed.
PanelWindow {
    id: win

    readonly property bool open: (Store.docs["runtime.ui"] && Store.docs["runtime.ui"].panel) === "notifications"
    readonly property var doc: Store.docs["svc.notifications"] || ({})
    readonly property var items: doc.items || []
    readonly property int maxH: 520
    readonly property int slide: 12
    property real p: 0
    property bool gate: false
    property bool shown: false
    visible: shown     // unmapped at idle: mapped-surface budget (docs/BENCH.md)

    Watch { doc: "svc.notifications" }

    // Newest first, grouped by app in order of each app's newest notification.
    readonly property var groups: {
        var order = [], by = {}
        var l = items.slice().sort(function (a, b) { return b.time - a.time })
        for (var i = 0; i < l.length; i++) {
            var k = l[i].app_name || ""
            if (!by[k]) { by[k] = { app: k, items: [] }; order.push(by[k]) }
            by[k].items.push(l[i])
        }
        return order
    }

    // Clears this output's bar, as Toasts does.
    BarConfig { id: bars; screen: win.screen }
    anchors { top: !bars.atBottom; bottom: bars.atBottom; right: true }
    // Room for the soft chrome's shadow round the card (K45; 0 under every other chrome), taken out of the margins so the
    // card stays where it was. Floating chromes (bar groups) keep a gap from the bar.
    readonly property int shade: Theme.softR
    readonly property int padL: shade
    readonly property int padR: Math.min(shade, bars.rightInset)
    readonly property int padT: bars.atBottom ? shade : Math.min(shade, bars.topInset)
    readonly property int padB: bars.atBottom ? Math.min(shade, bars.bottomInset) : shade
    readonly property int lead: Theme.groups ? Theme.gap : 0
    margins { top: bars.topInset - padT; bottom: bars.bottomInset - padB; right: bars.rightInset - padR }
    // Room for the card's hard shadow (keycap chrome) and a gap from the screen edge.
    implicitWidth: padL + card.width + Theme.shadowDy + padR
    implicitHeight: padT + lead + card.height + Theme.shadowDy + padB
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "kurashi-notifications"
    color: "transparent"
    mask: shown ? cardRegion : emptyRegion
    BackgroundEffect.blurRegion: shown ? cardRegion : emptyRegion
    Region { id: cardRegion; item: card }
    Region { id: emptyRegion }

    onOpenChanged: {
        if (open) {
            Store.act("notify.mark_read", {})
            anim.stop()
            if (!shown) { p = 0; gate = true; shown = true }
            else { anim.from = p; anim.to = 1; anim.start() }
        } else if (shown) {
            gate = false
            anim.stop(); anim.from = p; anim.to = 0; anim.start()
        }
    }
    NumberAnimation {
        id: anim
        target: win
        property: "p"
        duration: Theme.stdMs
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.enterCurve
        onFinished: if (win.p <= 0 && !win.open) win.shown = false
    }
    Connections {
        target: card.Window.window
        function onFrameSwapped() {
            if (win.gate) { win.gate = false; anim.from = win.p; anim.to = 1; anim.start() }
        }
    }

    Rectangle {
        id: card
        visible: win.shown
        // 400 px, wider (up to 480) when the title and its two buttons need it (a monospaced or wide face).
        width: Math.min(480, Math.max(400, titleText.implicitWidth + dnd.width + clear.width + 2 * Theme.gap + 2 * Theme.pad + 2))
        height: Math.min(win.maxH, head.height + (win.items.length > 0 ? list.contentHeight : empty.height) + 3 * Theme.pad)
        x: win.padL
        y: win.padT + win.lead - win.slide * (1 - win.p)
        radius: Theme.rLg + 4
        color: Theme.panel
        border.width: Theme.outlineW > 0 ? Theme.outlineW : 1
        border.color: Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline
        SoftShadow { anchors.fill: parent; radius: card.radius }
        Rectangle {
            z: -1
            visible: Theme.shadowDy > 0
            y: Theme.shadowDy
            width: card.width
            height: card.height
            radius: card.radius
            color: Theme.line
        }
        focus: true
        Keys.onEscapePressed: Store.act("ui.close")

        Row {
            id: head
            x: Theme.pad
            y: Theme.pad
            width: parent.width - 2 * Theme.pad
            height: 32
            spacing: Theme.gap
            Text {
                id: titleText
                width: parent.width - dnd.width - clear.width - 2 * parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                elide: Text.ElideRight
                text: I18n.tr("notifications.center.title")
            }
            Button {
                id: dnd
                anchors.verticalCenter: parent.verticalCenter
                label: I18n.tr("notifications.dnd")
                icon: win.doc.dnd === true ? "do_not_disturb_on" : "do_not_disturb_off"
                primary: win.doc.dnd === true
                onClicked: Store.act("notify.dnd", { on: !(win.doc.dnd === true) })
            }
            Button {
                id: clear
                anchors.verticalCenter: parent.verticalCenter
                label: I18n.tr("notifications.center.clear_all")
                icon: "clear_all"
                enabled: win.items.length > 0
                onClicked: Store.act("notify.dismiss", {})
            }
        }

        Column {
            id: empty
            visible: win.items.length === 0
            x: Theme.pad
            y: head.y + head.height + Theme.pad
            width: parent.width - 2 * Theme.pad
            spacing: Theme.xs
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "notifications_paused"
                glyph: ""
                size: 40
                color: Theme.dim
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                color: Theme.dim
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("notifications.center.empty")
            }
        }

        // Scroll cue: a fade over the bottom of the list while more notifications lie below it.
        // Static (no animation, no timer); it only exists while the list overflows.
        Rectangle {
            z: 1
            visible: list.visible && !list.atYEnd
            anchors { left: list.left; right: list.right; bottom: list.bottom }
            height: Theme.pad * 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Theme.container }
            }
        }

        Flickable {
            id: list
            visible: win.items.length > 0
            x: Theme.pad
            y: head.y + head.height + Theme.pad
            width: parent.width - 2 * Theme.pad
            height: parent.height - y - Theme.pad
            contentWidth: width
            contentHeight: body.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: body
                width: list.width
                spacing: Theme.pad
                Repeater {
                    model: win.groups
                    delegate: Column {
                        required property var modelData
                        width: body.width
                        spacing: Theme.gap
                        Text {
                            color: Theme.dim
                            font.pixelSize: Theme.fs - 2
                            font.family: Theme.fam(text, Theme.families)
                            text: modelData.app
                        }
                        Repeater {
                            model: modelData.items
                            delegate: NotificationCard {
                                required property var modelData
                                item: modelData
                                width: body.width - 2
                                swipeable: false
                                onDismissed: Store.act("notify.dismiss", { id: item.id })
                                onInvoked: key => Store.act("notify.invoke", { id: item.id, key: key })
                            }
                        }
                    }
                }
            }
        }
    }
}
