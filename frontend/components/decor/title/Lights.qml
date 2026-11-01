import QtQuick
import QtQuick.Shapes
import "../../../core"
import "../.."
import ".."

// Lights (W53.4): the traffic-light caption — Mac OS X 10.2–10.4's and macOS 11–14's title bar (docs/ux/styles.md §5,
// §6), drawn from the look's `[decor] title.*` alone so any look with round window buttons can use it (rule 4). The band
// in `title.fill` (`title.fill_dir`, `fill_inactive` without focus) at the material's alpha, the look's ground pattern
// over it (Jaguar's pinstripes run on through the caption), the top corners rounded `title.radius`, a hairline under it;
// the title centred (`title.align`) in `font.title` at `title.size`/`title.weight`, in `title.on` (`on_inactive`).
// The buttons sit on `title.buttons`' side, `title.inset` px in and vertically centred: discs `title.button_w` across,
// `title.button_gap` apart, always in the Mac's order — close (`title.close_fill`), minimize (`title.min_fill`), zoom
// (`title.max_fill`; "" = `error`, `warning`, `success`, each brought to a lamp's brightness from its role's hue). With
// `title.gloss` > 0 each is a gel (Aqua: a darker rim, the colour glowing up from its foot, a white highlight on its
// cap), at 0 a flat disc with a hairline rim (macOS 11+). Without focus they are grey. The marks (×, −, + / ⤢) show
// while the pointer is on the group, as on the Mac. A button the daemon does not list is not drawn — its place stays
// empty (Shōjiki: no dead button), so the others keep theirs. Both callers' contracts, as title/Gloss.qml. Static: one
// paint per size and colour; hover is one HoverHandler (0 frames idle).
TitleBase {
    id: cap
    property bool full: false
    signal pressed(string id)

    readonly property var fills: Theme.decor(active ? "title.fill" : "title.fill_inactive", [])
    readonly property color from: fills.length > 0 ? fills[0] : Theme.containerHigh
    readonly property color to: fills.length > 1 ? fills[1] : from
    readonly property bool vertical: Theme.decor("title.fill_dir", "vertical") === "vertical"
    readonly property real alpha: Theme.tok("color.surface_alpha", 1)
    readonly property string inkActive: Theme.decor("title.on", "")
    readonly property string inkInactive: Theme.decor("title.on_inactive", "")
    readonly property color ink: !active && inkInactive !== "" ? inkInactive : inkActive !== "" ? inkActive : Theme.fg
    readonly property real g: Math.max(0, Math.min(1, Theme.decor("title.gloss", 0)))
    readonly property real r: Math.max(0, Theme.decor("title.radius", -1))
    readonly property bool startSide: Theme.decor("title.buttons", "start") === "start"
    readonly property int d: Theme.decor("title.button_w", 0) > 0 ? Theme.decor("title.button_w", 0) : Math.max(10, Math.round(height * 0.5))
    readonly property int gap: Theme.decor("title.button_gap", -1) >= 0 ? Theme.decor("title.button_gap", -1) : 8
    readonly property int inset: Theme.decor("title.inset", -1) >= 0 ? Theme.decor("title.inset", -1) : 8
    readonly property real dpr: Screen.devicePixelRatio || 1
    readonly property real hair: Theme.crisp(1, dpr)
    // The lamps: a role's hue at a lamp's saturation and lightness (the WCAG stage may have darkened the role for text);
    // the lightness of each as measured: macOS 14 #fd5a57 / #fcbc3b / #24ca4b (0.67, 0.61, 0.47), Tiger's gel bodies alike.
    function lamp(key, fallback, l) {
        var role = Theme.decor(key, "")
        var c = Qt.color(role !== "" ? role : fallback)
        var h = c.hslHue < 0 ? 0 : c.hslHue
        return Qt.hsla(h, Math.max(0.72, c.hslSaturation), l, 1)
    }
    readonly property var colours: ({
        close: lamp("title.close_fill", Theme.error, 0.65),
        minimize: lamp("title.min_fill", Theme.warning, 0.61),
        maximize: lamp("title.max_fill", Theme.color("color.success", "#28c840"), 0.47)
    })
    readonly property color idle: Theme.darkScheme ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.16)

    // The daemon's buttons (Stage: [{id, action}]; TitleHost: names from the close button inward, close by `canClose`).
    readonly property var ids: {
        var b = buttons || []
        if (b.length > 0 && typeof b[0] === "object") return b.map(function (e) { return String(e.id) })
        var out = b.map(function (n) { return String(n) })
        if (canClose) out.push("close")
        return out
    }
    readonly property var actions: {
        var m = {}
        ;(buttons || []).forEach(function (e) { if (typeof e === "object") m[e.id] = e.action || "" })
        return m
    }
    readonly property var order: ["close", "minimize", "maximize"]
    function act(id) {
        cap.pressed(id)
        if (id === "close") cap.close()
        else cap.button(id)
    }

    // The band.
    Rectangle {
        anchors.fill: parent
        topLeftRadius: cap.r
        topRightRadius: cap.r
        gradient: Gradient {
            orientation: cap.vertical ? Gradient.Vertical : Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(cap.from, cap.alpha) }
            GradientStop { position: 1; color: Qt.alpha(cap.to, cap.alpha) }
        }
        Pattern { anchors.fill: parent; radius: cap.r }
    }
    // The hairline between the caption and the window's ground.
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: cap.hair
        color: Qt.alpha(Theme.outline, Theme.darkScheme ? 0.6 : 0.45)
    }
    Item {
        id: label
        readonly property real room: cap.inset + 3 * cap.d + 2 * cap.gap + 8
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            right: parent.right
            leftMargin: label.room
            rightMargin: label.room
        }
        height: txt.implicitHeight
        Text {
            id: txt
            width: parent.width
            text: cap.title
            elide: Text.ElideMiddle
            horizontalAlignment: Theme.decor("title.align", "center") === "center" ? Text.AlignHCenter : Text.AlignLeft
            color: cap.ink
            font.family: Theme.tok("font.title", "") || Theme.fam(cap.title, Theme.families)
            font.pixelSize: Theme.decor("title.size", 0) > 0 ? Theme.decor("title.size", 0) : Theme.fs
            font.weight: Theme.decor("title.weight", 400)
        }
    }
    Item {
        id: group
        x: cap.startSide ? cap.inset : cap.width - cap.inset - width
        anchors.verticalCenter: parent.verticalCenter
        width: 3 * cap.d + 2 * cap.gap
        height: cap.d
        HoverHandler { id: groupHover }
        Repeater {
            model: cap.order
            Item {
                id: b
                required property string modelData
                required property int index
                readonly property bool shown: cap.ids.indexOf(modelData) >= 0
                readonly property bool down: hit.pressed && hit.containsMouse
                readonly property color c: cap.active || groupHover.hovered ? cap.colours[modelData] : cap.idle
                visible: shown
                x: (cap.startSide ? index : 2 - index) * (cap.d + cap.gap)
                width: cap.d
                height: cap.d
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr(cap.actions[modelData] === "app_menu" ? "styles.title.app_menu"
                    : modelData === "maximize" && cap.full ? "styles.title.restore" : "styles.title." + modelData)
                Accessible.onPressAction: cap.act(modelData)
                // The rim, then the face: a gel (Aqua) or flat (macOS 11+).
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: cap.g > 0 ? Qt.darker(b.c, 1.55) : Qt.darker(b.c, 1.18)
                    opacity: cap.g > 0 || cap.active ? 1 : 0.9
                }
                Rectangle {
                    anchors { fill: parent; margins: cap.hair }
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.darker(b.c, 1 + (b.down ? 0.35 : 0.12) * cap.g + (b.down ? 0.12 : 0)) }
                        GradientStop { position: 0.55; color: Qt.darker(b.c, b.down ? 1.12 : 1) }
                        GradientStop { position: 1; color: Qt.lighter(b.c, 1 + (b.down ? 0.1 : 0.45) * cap.g) }
                    }
                }
                // The gel's highlight on the cap.
                Rectangle {
                    visible: cap.g > 0 && (cap.active || groupHover.hovered)
                    x: parent.width * 0.18; y: parent.height * 0.06
                    width: parent.width * 0.64; height: parent.height * 0.42
                    radius: height / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.92 * cap.g) }
                        GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.12 * cap.g) }
                    }
                }
                // The mark, while the pointer is on the group: × close, − minimize, + zoom on a gel (the 10.x mark) or ⤢
                // full screen on a flat lamp (macOS 11+).
                Shape {
                    id: glyph
                    visible: groupHover.hovered && cap.active
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    readonly property real m: Math.round(cap.d * 0.3)
                    readonly property real e: cap.d - m
                    readonly property real mid: cap.d / 2
                    readonly property color ink: Qt.darker(b.c, 2.8)
                    readonly property real sw: Math.max(1, cap.d / 11)
                    readonly property bool plus: b.modelData === "maximize" && cap.g > 0
                    readonly property bool arrows: b.modelData === "maximize" && cap.g === 0
                    ShapePath {
                        strokeColor: b.modelData === "close" ? glyph.ink : "transparent"
                        strokeWidth: glyph.sw
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        startX: glyph.m; startY: glyph.m
                        PathLine { x: glyph.e; y: glyph.e }
                        PathMove { x: glyph.e; y: glyph.m }
                        PathLine { x: glyph.m; y: glyph.e }
                    }
                    ShapePath {
                        strokeColor: b.modelData === "minimize" || glyph.plus ? glyph.ink : "transparent"
                        strokeWidth: glyph.sw
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        startX: glyph.m; startY: glyph.mid
                        PathLine { x: glyph.e; y: glyph.mid }
                    }
                    ShapePath {
                        strokeColor: glyph.plus ? glyph.ink : "transparent"
                        strokeWidth: glyph.sw
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        startX: glyph.mid; startY: glyph.m
                        PathLine { x: glyph.mid; y: glyph.e }
                    }
                    // ⤢: two heads, corner to corner.
                    ShapePath {
                        strokeColor: "transparent"
                        fillColor: glyph.arrows ? glyph.ink : "transparent"
                        startX: glyph.m - 0.5; startY: glyph.e + 0.5
                        PathLine { x: glyph.m - 0.5; y: glyph.mid - 0.5 }
                        PathLine { x: glyph.mid + 0.5; y: glyph.e + 0.5 }
                        PathLine { x: glyph.m - 0.5; y: glyph.e + 0.5 }
                        PathMove { x: glyph.e + 0.5; y: glyph.m - 0.5 }
                        PathLine { x: glyph.e + 0.5; y: glyph.mid + 0.5 }
                        PathLine { x: glyph.mid - 0.5; y: glyph.m - 0.5 }
                        PathLine { x: glyph.e + 0.5; y: glyph.m - 0.5 }
                    }
                }
                MouseArea {
                    id: hit
                    anchors.fill: parent
                    anchors.margins: -Math.round(cap.gap / 2)
                    hoverEnabled: true
                    onClicked: cap.act(b.modelData)
                }
            }
        }
    }
}
