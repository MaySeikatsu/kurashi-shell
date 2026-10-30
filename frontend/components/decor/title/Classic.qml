import QtQuick
import "../../../core"
import "../.."
import ".."

// Classic (W53.1): the bevel-era caption — Windows 9x/2000's title bar, drawn from the look's `[decor] title.*` alone so any
// look with raised caption buttons can use it (rule 4: no name is compared). A solid or gradient fill (`title.fill`, and
// `title.fill_inactive` with `title.on_inactive` while the window is not focused), bold text at the start, and the
// buttons as raised bevel keys of `title.button_w` × `title.button_h` px, `title.inset` px in from the caption's edges and
// `title.button_gap` px apart from the close button, each with its mark drawn on whole pixels (the 8 × 7 cross, the
// 6 × 2 bar, the box with its heavy top edge, two boxes for restore) — sunk 1 px while pressed.
// Two callers, one part: TitleHost hands `canClose` and `buttons` as names from the close button inward and listens to
// `close`/`button(name)`; Stage (W53.0b, contract row 560) hands the daemon's `buttons` as `[{id, action}]` in drawing
// order and `full`, and listens to `pressed(id)`. Both are honoured; every button that is drawn acts (Shōjiki). Static:
// one paint per size and colour (0 frames idle).
TitleBase {
    id: cap
    // Stage's: the card is full screen (maximize draws as restore).
    property bool full: false
    signal pressed(string id)

    readonly property var fills: Theme.decor(active ? "title.fill" : "title.fill_inactive", [])
    readonly property color from: fills.length > 0 ? fills[0] : Theme.accent
    readonly property color to: fills.length > 1 ? fills[1] : from
    readonly property string onActive: Theme.decor("title.on", "")
    readonly property string onInactive: Theme.decor("title.on_inactive", "")
    readonly property color ink: !active && onInactive !== "" ? onInactive
        : onActive !== "" ? onActive : Theme.fgOnAccent
    readonly property bool startSide: Theme.decor("title.buttons", "end") === "start"
    readonly property real dpr: Screen.devicePixelRatio || 1
    function px(v) { return Math.round(v * dpr) / dpr }
    readonly property int inset: Math.max(0, Theme.decor("title.inset", -1) >= 0 ? Theme.decor("title.inset", -1) : 2)
    readonly property int bh: Theme.decor("title.button_h", 0) > 0 ? Theme.decor("title.button_h", 0)
        : Math.max(10, Math.round(height) - 2 * inset)
    readonly property int bw: Theme.decor("title.button_w", 0) > 0 ? Theme.decor("title.button_w", 0) : bh + 2
    readonly property int gap: Theme.decor("title.button_gap", -1) >= 0 ? Theme.decor("title.button_gap", -1) : 2
    // The buttons in drawing order (start → end of the caption), as ids. Stage's entries are objects in that order;
    // TitleHost's names run from the close button inward.
    readonly property var ids: {
        var b = buttons || []
        if (b.length > 0 && typeof b[0] === "object")
            return b.map(function (e) { return String(e.id) })
        var out = b.slice().reverse().map(function (n) { return String(n) })
        if (canClose) out.push("close")
        return out
    }
    readonly property var actions: {
        var m = {}
        ;(buttons || []).forEach(function (e) { if (typeof e === "object") m[e.id] = e.action || "" })
        return m
    }
    readonly property real rowW: {
        var w = 0
        for (var i = 0; i < ids.length; i++) w += bw + (ids[i] === "close" && i > 0 ? gap : 0)
        return w
    }

    function act(id) {
        cap.pressed(id)
        if (id === "close") cap.close()
        else cap.button(id)
    }

    Rectangle {
        anchors.fill: parent
        radius: Math.max(0, Theme.decor("title.radius", -1))
        gradient: Gradient {
            orientation: Theme.decor("title.fill_dir", "horizontal") === "vertical" ? Gradient.Vertical : Gradient.Horizontal
            GradientStop { position: 0; color: cap.from }
            GradientStop { position: 1; color: cap.to }
        }
    }
    Icon {
        id: glyph
        visible: cap.icon !== ""
        x: cap.startSide ? cap.inset + cap.rowW + 3 : cap.inset
        anchors.verticalCenter: parent.verticalCenter
        name: cap.icon
        size: 16
        color: cap.ink
    }
    PixelLabel {
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            leftMargin: (glyph.visible ? glyph.x + glyph.width + 3 : (cap.startSide ? cap.inset + cap.rowW + 3 : 3))
            right: parent.right
            rightMargin: cap.startSide ? 3 : cap.inset + cap.rowW + 3
        }
        text: cap.title
        color: cap.ink
        horizontalAlignment: Theme.decor("title.align", "start") === "center" ? Text.AlignHCenter : Text.AlignLeft
        weight: Theme.decor("title.weight", 700)
    }
    Row {
        x: cap.startSide ? cap.inset : cap.width - cap.inset - cap.rowW
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
            model: cap.ids
            Item {
                id: b
                required property string modelData
                required property int index
                readonly property bool down: hit.pressed && hit.containsMouse
                // The gap sits before the close button (98: minimize and maximize touch, close stands apart).
                width: cap.bw + (modelData === "close" && index > 0 ? cap.gap : 0)
                height: cap.bh
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr(cap.actions[modelData] === "app_menu" ? "styles.title.app_menu"
                    : modelData === "maximize" && cap.full ? "styles.title.restore" : "styles.title." + modelData)
                Accessible.onPressAction: cap.act(modelData)
                Item {
                    id: key
                    x: parent.width - cap.bw
                    width: cap.bw
                    height: cap.bh
                    Rectangle { anchors.fill: parent; color: Theme.surface }
                    BevelEdge {
                        anchors.fill: parent
                        w: Theme.crisp(1, cap.dpr)
                        sunk: b.down
                    }
                    // The mark, on whole pixels, 1 px down-right while pressed.
                    Item {
                        id: mark
                        readonly property int ox: b.down ? 1 : 0
                        readonly property color c: Theme.fg
                        x: ox; y: ox
                        width: parent.width; height: parent.height
                        // × : 8 × 7, two-pixel strokes (rows 0..6), centred.
                        Repeater {
                            model: b.modelData === "close" ? 7 : 0
                            Item {
                                required property int index
                                readonly property int d: index <= 3 ? index : 6 - index
                                readonly property int ty: Math.floor((cap.bh - 7) / 2)
                                readonly property int lx: Math.floor((cap.bw - 8) / 2)
                                Rectangle { x: parent.lx + parent.d; y: parent.ty + parent.index; width: 2; height: 1; color: mark.c }
                                Rectangle { x: parent.lx + 6 - parent.d; y: parent.ty + parent.index; width: 2; height: 1; color: mark.c }
                            }
                        }
                        // _ : a 6 × 2 bar near the bottom.
                        Rectangle {
                            visible: b.modelData === "minimize"
                            x: Math.floor((cap.bw - 8) / 2); y: cap.bh - 5
                            width: 6; height: 2
                            color: mark.c
                        }
                        // □ : a 9 × 9 box with a two-pixel top; restore: two 6 × 6 boxes, the back one up-right.
                        Item {
                            visible: b.modelData === "maximize" && !cap.full
                            x: Math.floor((cap.bw - 9) / 2); y: Math.floor((cap.bh - 9) / 2)
                            width: 9; height: 9
                            Rectangle { width: 9; height: 2; color: mark.c }
                            Rectangle { y: 8; width: 9; height: 1; color: mark.c }
                            Rectangle { width: 1; height: 9; color: mark.c }
                            Rectangle { x: 8; width: 1; height: 9; color: mark.c }
                        }
                        Item {
                            visible: b.modelData === "maximize" && cap.full
                            x: Math.floor((cap.bw - 9) / 2); y: Math.floor((cap.bh - 9) / 2)
                            width: 9; height: 9
                            component Box: Item {
                                width: 6; height: 6
                                Rectangle { width: 6; height: 2; color: mark.c }
                                Rectangle { y: 5; width: 6; height: 1; color: mark.c }
                                Rectangle { width: 1; height: 6; color: mark.c }
                                Rectangle { x: 5; width: 1; height: 6; color: mark.c }
                            }
                            Box { x: 3; y: 0 }
                            Rectangle { x: 0; y: 3; width: 6; height: 6; color: Theme.surface }
                            Box { x: 0; y: 3 }
                        }
                    }
                    MouseArea {
                        id: hit
                        anchors.fill: parent
                        onClicked: cap.act(b.modelData)
                    }
                }
            }
        }
    }
}
