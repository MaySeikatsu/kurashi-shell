import QtQuick
import QtQuick.Effects
import "../../../core"
import "../.."
import ".."

// Glass (W53.2): the glass caption — Windows 7's Aero title bar (docs/ux/styles.md §3), drawn from the look's
// `[decor] title.*` alone (rule 4). Measured on a real Windows 7 capture at 1:1, commons.wikimedia.org's
// "SeaMonkey 2.46 on Windows 7.png" (window x 14–1068; caption y 12–41; buttons y 13–31): the band is the window's glass
// — `title.fill`'s role over the blurred desktop (the card's own blur), two faint diagonal highlights — with the title
// dark (`title.on`) in `font.title` (`title.family`: Segoe UI → Selawik) at `title.size`, a soft light glow behind it
// (`title.text_effect = glow`, 7's caption glow); the buttons a joined group hanging from the top edge `title.inset` px
// from the end: `title.button_w` × `title.button_h` glass keys and the `title.close_w` wide close key in
// `title.close_fill` (7's red gel), sharing 1 px rims, the group's bottom corners rounded `title.button_radius`, each face
// split at half height (light glass above, a glow rising from the foot), white marks with a dark rim. Hover lights a key
// (blue on the glass keys, a hotter red on close). Both callers' contracts as title/Classic.qml (TitleHost's names,
// Stage's `[{id, action}]`, `full`, `pressed(id)`). Every button drawn acts (Shōjiki). Static (0 frames idle).
TitleBase {
    id: cap
    property bool full: false
    signal pressed(string id)

    readonly property var fills: Theme.decor(active ? "title.fill" : "title.fill_inactive", [])
    readonly property color glass: fills.length > 0 ? fills[0] : Theme.accent
    readonly property string onActive: Theme.decor("title.on", "")
    readonly property string onInactive: Theme.decor("title.on_inactive", "")
    readonly property color ink: !active && onInactive !== "" ? onInactive
        : onActive !== "" ? onActive : Theme.fg
    // The glass's opacity follows the theme's (reduce transparency: opaque).
    readonly property real a: Theme.tok("color.surface_alpha", 0.82)
    readonly property real r: Math.max(0, Theme.decor("title.radius", -1))
    readonly property bool startSide: Theme.decor("title.buttons", "end") === "start"
    readonly property int inset: Theme.decor("title.inset", -1) >= 0 ? Theme.decor("title.inset", -1) : 6
    readonly property int bh: Theme.decor("title.button_h", 0) > 0 ? Theme.decor("title.button_h", 0) : 19
    readonly property int bw: Theme.decor("title.button_w", 0) > 0 ? Theme.decor("title.button_w", 0) : 27
    readonly property int cw: Theme.decor("title.close_w", 0) > 0 ? Theme.decor("title.close_w", 0) : 2 * bw - 6
    readonly property int br: Theme.decor("title.button_radius", -1) >= 0 ? Theme.decor("title.button_radius", -1) : 5
    readonly property string closeRole: Theme.decor("title.close_fill", "")
    readonly property color closeFill: closeRole !== "" ? closeRole : Theme.error
    readonly property real dpr: Screen.devicePixelRatio || 1
    readonly property real hair: Theme.crisp(1, dpr)
    readonly property color rim: Qt.rgba(0.13, 0.16, 0.2, 0.75)

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
        for (var i = 0; i < ids.length; i++) w += wOf(ids[i])
        return Math.max(0, w - (ids.length - 1) * hair)
    }
    function act(id) {
        cap.pressed(id)
        if (id === "close") cap.close()
        else cap.button(id)
    }

    // The glass: the tint, a soft light over the upper part, two faint diagonal highlights.
    Item {
        anchors.fill: parent
        clip: true
        Rectangle {
            anchors.fill: parent
            topLeftRadius: cap.r
            topRightRadius: cap.r
            color: Qt.alpha(cap.glass, (cap.active ? 0.62 : 0.4) * cap.a)
        }
        Rectangle {
            anchors.fill: parent
            topLeftRadius: cap.r
            topRightRadius: cap.r
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.34) }
                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.12) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.04) }
            }
        }
        Rectangle {
            x: cap.width * 0.18; y: -cap.height
            width: cap.height * 1.1; height: cap.height * 3
            rotation: 35
            color: Qt.rgba(1, 1, 1, 0.10)
        }
        Rectangle {
            x: cap.width * 0.24; y: -cap.height
            width: cap.height * 0.35; height: cap.height * 3
            rotation: 35
            color: Qt.rgba(1, 1, 1, 0.08)
        }
    }
    Icon {
        id: glyph
        visible: cap.icon !== ""
        x: cap.startSide ? cap.inset + cap.rowW + 6 : 8
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
            leftMargin: glyph.visible ? glyph.x + glyph.width + 6 : (cap.startSide ? cap.inset + cap.rowW + 8 : 9)
            right: parent.right
            rightMargin: cap.startSide ? 8 : cap.inset + cap.rowW + 8
        }
        height: txt.implicitHeight
        readonly property string fam: Theme.tok("font.title", "") || Theme.fam(cap.title, Theme.families)
        // 7's caption glow: a soft light cloud behind the text, as wide as the text.
        RectangularShadow {
            visible: Theme.decor("title.text_effect", "none") === "glow" && cap.title !== ""
            x: -6
            y: 1
            width: Math.min(label.width, txt.contentWidth) + 12
            height: txt.implicitHeight - 2
            radius: height / 2
            blur: 9
            spread: 0
            color: Qt.rgba(1, 1, 1, cap.active ? 0.85 : 0.6)
        }
        Text {
            visible: Theme.decor("title.text_effect", "none") === "shadow"
            x: 1; y: 1
            width: parent.width
            text: txt.text
            elide: Text.ElideRight
            font: txt.font
            color: Qt.rgba(0, 0, 0, 0.5)
        }
        Text {
            id: txt
            width: parent.width
            text: cap.title
            elide: Text.ElideRight
            horizontalAlignment: Theme.decor("title.align", "start") === "center" ? Text.AlignHCenter : Text.AlignLeft
            color: cap.ink
            font.family: label.fam
            font.pixelSize: Theme.decor("title.size", 0) > 0 ? Theme.decor("title.size", 0) : Theme.fs
            font.weight: Theme.decor("title.weight", 400)
        }
    }
    Row {
        x: cap.startSide ? cap.inset : cap.width - cap.inset - cap.rowW
        y: 0
        spacing: -cap.hair
        Repeater {
            id: rep
            model: cap.ids
            Item {
                id: b
                required property string modelData
                required property int index
                readonly property bool isClose: modelData === "close"
                readonly property bool first: index === 0
                readonly property bool last: index === cap.ids.length - 1
                readonly property bool down: hit.pressed && hit.containsMouse
                readonly property bool hot: hit.containsMouse
                width: cap.wOf(modelData)
                height: cap.bh
                opacity: cap.active || hot ? 1 : 0.75
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr(cap.actions[modelData] === "app_menu" ? "styles.title.app_menu"
                    : modelData === "maximize" && cap.full ? "styles.title.restore" : "styles.title." + modelData)
                Accessible.onPressAction: cap.act(modelData)
                // The rim and the face, the group's outer bottom corners rounded.
                Rectangle {
                    id: shell
                    anchors.fill: parent
                    bottomLeftRadius: b.first ? cap.br : 0
                    bottomRightRadius: b.last ? cap.br : 0
                    color: b.isClose ? cap.closeFill : Qt.alpha(Qt.lighter(cap.glass, 1.1), 0.75)
                    border.width: cap.hair
                    border.color: cap.rim
                }
                Item {
                    anchors { fill: parent; margins: cap.hair }
                    clip: true
                    // Above the split: light glass (or the gel's light top); below: the deeper face with a glow rising.
                    Rectangle {
                        width: parent.width; height: parent.height
                        bottomLeftRadius: b.first ? Math.max(0, cap.br - 1) : 0
                        bottomRightRadius: b.last ? Math.max(0, cap.br - 1) : 0
                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: b.isClose ? Qt.tint(cap.closeFill, Qt.rgba(1, 1, 1, b.hot ? 0.5 : 0.42))
                                    : Qt.rgba(1, 1, 1, b.hot ? 0.75 : 0.6)
                            }
                            GradientStop {
                                position: 0.49
                                color: b.isClose ? Qt.tint(cap.closeFill, Qt.rgba(1, 1, 1, b.hot ? 0.38 : 0.28))
                                    : Qt.rgba(1, 1, 1, b.hot ? 0.55 : 0.38)
                            }
                            GradientStop {
                                position: 0.5
                                color: b.isClose ? (b.down ? Qt.darker(cap.closeFill, 1.5) : b.hot ? Qt.lighter(cap.closeFill, 1.12) : cap.closeFill)
                                    : (b.down ? Qt.alpha(Qt.darker(Theme.accent, 1.3), 0.6) : b.hot ? Qt.alpha(Theme.accent, 0.45) : Qt.rgba(1, 1, 1, 0.12))
                            }
                            GradientStop {
                                position: 0.8
                                color: b.isClose ? Qt.darker(cap.closeFill, b.down ? 1.6 : 1.05)
                                    : (b.hot ? Qt.alpha(Qt.lighter(Theme.accent, 1.3), 0.5) : Qt.rgba(1, 1, 1, 0.16))
                            }
                            GradientStop {
                                position: 1
                                color: b.isClose ? Qt.tint(cap.closeFill, Qt.rgba(1, 1, 1, b.hot ? 0.45 : 0.32))
                                    : (b.hot ? Qt.alpha(Qt.lighter(Theme.accent, 1.8), 0.85) : Qt.rgba(1, 1, 1, 0.38))
                            }
                        }
                    }
                }
                CaptionGlyph {
                    readonly property real s: b.isClose ? Math.round(cap.bh * 0.47) : Math.round(cap.bh * 0.42)
                    kind: b.modelData === "maximize" && cap.full ? "restore" : b.modelData
                    size: s
                    stroke: b.isClose ? 2.5 : 2
                    ink: Qt.rgba(1, 1, 1, 1)
                    edge: cap.rim
                    x: Math.round((b.width - s) / 2)
                    y: Math.round((b.height - s) / 2)
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
