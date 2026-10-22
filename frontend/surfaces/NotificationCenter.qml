import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"
import "../components/launcher"

// Notification center: content-sized overlay, shown while the daemon's runtime.ui.panel is "notifications" (opened by
// the island `notifications` face, `notifications.center`). Unmapped while closed: nothing is rendered.
//
// W34 (docs/ux/motion.md): under a top or bottom bar it grows out of the island pill — where the notifications face
// lives — as one shape (BarMorph: the island's MorphShape, two springs, the liquid neck, the pill's face in its head) and
// folds back into it; the card hangs under the bar's centre, like the island's own views, and the window covers the
// bar's strip above it while the shape is out. Without one (a side bar, no bar) it slides in at the top right, as before.
PanelWindow {
    id: win

    readonly property bool open: (Store.docs["runtime.ui"] && Store.docs["runtime.ui"].panel) === "notifications"
    readonly property var doc: Store.docs["svc.notifications"] || ({})
    readonly property var items: doc.items || []
    readonly property int maxH: 520
    // K59: this window's tile set, shared by its reliefs, and the pointer light's sensor. K61: the card's carry while it
    // slides in (`texture.sheet = carried`); 0 in the morph, whose shape carries its own.
    property var tileSheet: tilesLoader.item
    readonly property point sheetCarry: morph.carry
    Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
    LightSense {}
    readonly property bool shown: morph.shown
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

    // Clears this output's bar, as Toasts does (the slide); the morph hangs from it.
    BarConfig { id: bars; screen: win.screen }
    readonly property bool morphing: bars.atTop || bars.atBottom
    // The morph: one vertical edge (the compositor centres the window on the bar), margin 0. The slide: the top right.
    anchors { top: !bars.atBottom; bottom: bars.atBottom; right: !morphing }
    // Room for the soft chrome's shadow round the card (K45; 0 under every other chrome), taken out of the margins so the
    // card stays where it was. Floating chromes (bar groups) keep a gap from the bar.
    readonly property int shade: Theme.softR
    readonly property int padL: shade
    readonly property int padR: Math.min(shade, bars.rightInset)
    readonly property int padT: bars.atBottom ? shade : Math.min(shade, bars.topInset)
    readonly property int padB: bars.atBottom ? Math.min(shade, bars.bottomInset) : shade
    readonly property int lead: Theme.groups ? Theme.gap : 0
    margins {
        top: morphing ? 0 : bars.topInset - padT
        bottom: morphing ? 0 : bars.bottomInset - padB
        right: morphing ? 0 : bars.rightInset - padR
    }
    // Room for the card's hard shadow (keycap chrome) and a gap from the screen edge.
    implicitWidth: morphing ? morph.width : padL + card.width + Theme.shadowDy + padR
    implicitHeight: morphing ? morph.height : padT + lead + card.height + Theme.shadowDy + padB
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.namespace: "kurashi-notifications"
    color: "transparent"
    mask: shown ? cardRegion : emptyRegion
    // The shape changes size every frame of its morph: blur only behind the card at rest.
    BackgroundEffect.blurRegion: shown && morph.settled ? cardRegion : emptyRegion
    Region { id: cardRegion; item: morph.cardItem }
    Region { id: emptyRegion }

    onOpenChanged: if (open) Store.act("notify.mark_read", {})

    BarMorph {
        id: morph
        // The slide keeps the card where it was: past the margins' room for the shadow.
        x: morph.morph ? 0 : win.padL - morph.shade
        y: morph.morph ? 0 : win.padT + win.lead - morph.shade
        outName: win.screen ? win.screen.name : ""
        onBar: win.morphing
        flip: bars.atBottom
        open: win.open
        cardW: card.width
        cardH: card.height
        slide: 12

        Rectangle {
            id: card
            // 400 px, wider (up to 480) when the title and its two buttons need it (a monospaced or wide face).
            width: Math.min(480, Math.max(400, titleText.implicitWidth + dnd.width + clear.width + 2 * Theme.gap + 2 * Theme.pad + 2))
            height: Math.min(win.maxH, head.height + (win.items.length > 0 ? list.contentHeight : empty.height) + 3 * Theme.pad)
            radius: Theme.rLg + 4
            // In the morph the shape is the card's chrome (fill, outline, shadows, material); this only holds the content.
            readonly property bool chrome: !morph.morph
            color: chrome ? Theme.panel : "transparent"
            border.width: !chrome ? 0 : (Theme.outlineW > 0 ? Theme.outlineW : 1)
            border.color: Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline
            SoftShadow { anchors.fill: parent; radius: card.radius; amount: card.chrome ? 1 : 0 }
            // K59: the card is a material area; the relief lies under the content (over it with texture.text).
            Loader {
                z: Theme.texText ? 2 : 0
                anchors.fill: parent
                anchors.margins: Theme.outlineW
                active: Theme.texShell && card.chrome
                sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, card.radius - Theme.outlineW) }
            }
            Rectangle {
                z: -1
                visible: Theme.shadowDy > 0 && card.chrome
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
}
