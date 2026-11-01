import QtQuick
import "../../../core"
import "../.."
import ".."

// Gloss (W53.2): the glossy-band caption — Windows XP's Luna title bar (docs/ux/styles.md §2), drawn from the look's
// `[decor] title.*` alone so any look with a glossy band can use it (rule 4). Measured on guidebookgallery.org's
// pics/gui/desktop/full/winxppro.png (the active "Remote Desktop Connection" window, y 332–360; the inactive
// "My Computer"): a vertical band in `title.fill` (body, glow) with a bright line under its top edge, a darker body, a
// glow in its lower third and two darkening px at the foot (`title.gloss` scales the light; `title.fill_inactive` and
// `title.on_inactive` while the window has no focus), the top corners rounded `title.radius`; the title in `font.title`
// (`title.family`: Trebuchet MS → Fira Sans) at `title.size` and `title.weight` with XP's 1 px shadow
// (`title.text_effect`); the buttons `title.button_w` × `title.button_h` plates, `title.inset` px from the band's top and
// end, `title.button_gap` apart, rounded `title.button_radius`, a 1 px light rim, glossy faces lit from the top left —
// the close plate in `title.close_fill` (XP's red), the others in the band's glow — with white marks (CaptionGlyph).
// Both callers' contracts, as title/Classic.qml: TitleHost's `canClose` and button names (from the close button inward)
// with `close`/`button(name)`, and Stage's `buttons` as `[{id, action}]` in drawing order with `full` and `pressed(id)`.
// Every button drawn acts (Shōjiki). Static: one paint per size and colour (0 frames idle); hover lightens a plate.
TitleBase {
    id: cap
    property bool full: false
    signal pressed(string id)

    readonly property var fills: Theme.decor(active ? "title.fill" : "title.fill_inactive", [])
    readonly property color from: fills.length > 0 ? fills[0] : Theme.accent
    readonly property color to: fills.length > 1 ? fills[1] : Qt.lighter(from, 1.12)
    readonly property string onActive: Theme.decor("title.on", "")
    readonly property string onInactive: Theme.decor("title.on_inactive", "")
    readonly property color ink: !active && onInactive !== "" ? onInactive
        : onActive !== "" ? onActive : Theme.fgOnAccent
    readonly property real g: Math.max(0, Math.min(1, Theme.decor("title.gloss", 0.5) * 2))
    readonly property real h: Math.max(1, height)
    readonly property real r: Math.max(0, Theme.decor("title.radius", -1))
    readonly property bool startSide: Theme.decor("title.buttons", "end") === "start"
    readonly property int inset: Theme.decor("title.inset", -1) >= 0 ? Theme.decor("title.inset", -1) : 4
    readonly property int bh: Theme.decor("title.button_h", 0) > 0 ? Theme.decor("title.button_h", 0)
        : Math.max(12, Math.round(height) - 2 * inset)
    readonly property int bw: Theme.decor("title.button_w", 0) > 0 ? Theme.decor("title.button_w", 0) : bh
    readonly property int cw: Theme.decor("title.close_w", 0) > 0 ? Theme.decor("title.close_w", 0) : bw
    readonly property int gap: Theme.decor("title.button_gap", -1) >= 0 ? Theme.decor("title.button_gap", -1) : 2
    readonly property int br: Theme.decor("title.button_radius", -1) >= 0 ? Theme.decor("title.button_radius", -1) : 3
    readonly property string closeRole: Theme.decor("title.close_fill", "")
    readonly property color closeFill: closeRole !== "" ? closeRole : Theme.error
    readonly property int by: Math.max(0, Math.min(inset, Math.round(height) - bh))
    readonly property real dpr: Screen.devicePixelRatio || 1
    readonly property real hair: Theme.crisp(1, dpr)

    // The buttons in drawing order (start → end of the caption), as ids (Classic.qml's rule).
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
    function wOf(id) { return id === "close" ? cw : bw }
    readonly property real rowW: {
        var w = 0
        for (var i = 0; i < ids.length; i++) w += wOf(ids[i]) + (i > 0 ? gap : 0)
        return w
    }
    function act(id) {
        cap.pressed(id)
        if (id === "close") cap.close()
        else cap.button(id)
    }
    function at(px) { return Math.max(0, Math.min(1, px / h)) }

    // The band.
    Rectangle {
        anchors.fill: parent
        topLeftRadius: cap.r
        topRightRadius: cap.r
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.darker(cap.from, 1.0) }
            GradientStop { position: cap.at(1); color: Qt.tint(cap.to, Qt.rgba(1, 1, 1, 0.26 * cap.g)) }
            GradientStop { position: cap.at(2.4); color: Qt.tint(cap.to, Qt.rgba(1, 1, 1, 0.12 * cap.g)) }
            GradientStop { position: cap.at(4); color: Qt.darker(cap.from, 1.0 + 0.04 * cap.g) }
            GradientStop { position: cap.at(cap.h * 0.36); color: Qt.darker(cap.from, 1.0 + 0.03 * cap.g) }
            GradientStop { position: cap.at(cap.h * 0.68); color: cap.to }
            GradientStop { position: cap.at(cap.h * 0.86); color: cap.to }
            GradientStop { position: cap.at(cap.h - 2); color: Qt.darker(cap.from, 1.0 + 0.05 * cap.g) }
            GradientStop { position: 1; color: Qt.darker(cap.from, 1.0 + 0.16 * cap.g) }
        }
    }
    Icon {
        id: glyph
        visible: cap.icon !== ""
        x: cap.startSide ? cap.inset + cap.rowW + 6 : 6
        anchors.verticalCenter: parent.verticalCenter
        name: cap.icon
        size: 16
        color: cap.ink
    }
    Item {
        id: label
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            leftMargin: glyph.visible ? glyph.x + glyph.width + 5 : (cap.startSide ? cap.inset + cap.rowW + 8 : 7)
            right: parent.right
            rightMargin: cap.startSide ? 7 : cap.inset + cap.rowW + 6
        }
        height: txt.implicitHeight
        readonly property string fam: Theme.tok("font.title", "") || Theme.fam(cap.title, Theme.families)
        Text {
            visible: Theme.decor("title.text_effect", "none") === "shadow"
            x: 1; y: 1
            width: parent.width
            text: txt.text
            elide: Text.ElideRight
            horizontalAlignment: txt.horizontalAlignment
            font: txt.font
            color: Qt.darker(cap.from, 2.4)
        }
        Text {
            id: txt
            width: parent.width
            text: cap.title
            elide: Text.ElideRight
            horizontalAlignment: Theme.decor("title.align", "start") === "center" ? Text.AlignHCenter : Text.AlignLeft
            color: cap.ink
            font.family: label.fam
            font.pixelSize: Theme.decor("title.size", 0) > 0 ? Theme.decor("title.size", 0) : Theme.fsTitle
            font.weight: Theme.decor("title.weight", 700)
        }
    }
    Row {
        x: cap.startSide ? cap.inset : cap.width - cap.inset - cap.rowW
        y: cap.by
        spacing: cap.gap
        Repeater {
            model: cap.ids
            Item {
                id: b
                required property string modelData
                readonly property bool isClose: modelData === "close"
                readonly property bool down: hit.pressed && hit.containsMouse
                readonly property color face: isClose ? Qt.lighter(cap.closeFill, 1.25) : (cap.active ? cap.to : cap.from)
                width: cap.wOf(modelData)
                height: cap.bh
                opacity: cap.active ? 1 : 0.7
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr(cap.actions[modelData] === "app_menu" ? "styles.title.app_menu"
                    : modelData === "maximize" && cap.full ? "styles.title.restore" : "styles.title." + modelData)
                Accessible.onPressAction: cap.act(modelData)
                // The light rim, then the glossy face lit from the top left.
                Rectangle {
                    anchors.fill: parent
                    radius: cap.br
                    color: Qt.alpha(cap.ink, 0.95)
                }
                Rectangle {
                    anchors { fill: parent; margins: cap.hair }
                    radius: Math.max(0, cap.br - 1)
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0; color: b.down ? Qt.darker(b.face, 1.15) : Qt.tint(b.face, Qt.rgba(1, 1, 1, hit.containsMouse ? 0.42 : 0.32)) }
                        GradientStop { position: 0.45; color: b.down ? Qt.darker(b.face, 1.1) : Qt.tint(b.face, Qt.rgba(1, 1, 1, hit.containsMouse ? 0.24 : 0.14)) }
                        GradientStop { position: 1; color: b.down ? Qt.darker(b.face, 1.25) : Qt.darker(b.face, hit.containsMouse ? 1.02 : 1.12) }
                    }
                }
                // A soft sheen along the top-left edge.
                Rectangle {
                    x: 2 * cap.hair; y: 2 * cap.hair
                    width: parent.width * 0.55; height: parent.height * 0.5
                    radius: Math.max(0, cap.br - 1)
                    visible: !b.down
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.22) }
                        GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                    }
                }
                CaptionGlyph {
                    readonly property real s: Math.round(Math.min(b.width, b.height) * 0.43)
                    kind: b.modelData === "maximize" && cap.full ? "restore" : b.modelData
                    size: s
                    stroke: Math.max(2, Math.round(s / 4))
                    ink: cap.ink
                    x: Math.round((b.width - s) / 2) + (b.down ? 1 : 0)
                    y: Math.round((b.height - s) / 2) + (b.down ? 1 : 0)
                }
                MouseArea {
                    id: hit
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: cap.act(b.modelData)
                }
            }
        }
    }
}
