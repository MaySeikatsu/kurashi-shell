import QtQuick
import QtQuick.Shapes
import "../../../core"
import "../.."

// Fluent (session 18, I325): Windows 11's caption — WinUI 3's TitleBar and its caption buttons. No band of its own: the
// card's material (Mica/Acrylic) runs under the title, as 11's windows do; a 16 px icon 16 px in, the title in Caption
// type (12 px, `title.size`) after it; the buttons 46 × 32 at the end, each a thin 10 px glyph (Segoe Fluent Icons'
// ChromeClose/Minimize/Maximize/Restore, drawn here as 1 px lines). Hover lays SubtleFillColorSecondary under a key
// (light #0A000000, dark #0FFFFFFF), press the tertiary fill; the close key turns #C42B1C with a white glyph and keeps
// the card's top corner. An inactive caption's text and glyphs take TextFillColorDisabled (36 %). Fluent's default is no
// title bar at all (the fluent style's `title_bar.buttons = off`: 11's flyouts have none); this part draws one when the
// user switches it on. Contracts as title/Glass.qml (TitleHost's names, Stage's `[{id, action}]`, `full`, `pressed(id)`).
// Every button drawn acts (Shōjiki). Static (0 frames idle).
TitleBase {
    id: cap
    property bool full: false
    signal pressed(string id)

    readonly property color ink: Theme.fg
    readonly property real dim: active ? 1 : 0.36
    readonly property bool dark: Theme.darkScheme
    readonly property int bw: Theme.decor("title.button_w", 0) > 0 ? Theme.decor("title.button_w", 0) : 46
    readonly property int bh: Math.max(1, cap.height)
    readonly property real r: Theme.decor("title.radius", -1) >= 0 ? Theme.decor("title.radius", -1) : Theme.rLg
    readonly property color closeRed: Theme.decor("title.close_fill", "") !== "" ? Theme.decor("title.close_fill", "") : "#c42b1c"
    readonly property real dpr: Screen.devicePixelRatio || 1
    readonly property real hair: Theme.crisp(1, dpr)
    implicitHeight: Theme.crisp(Theme.decor("title.height", 32), dpr)

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
    function act(id) {
        cap.pressed(id)
        if (id === "close") cap.close()
        else cap.button(id)
    }

    Icon {
        id: glyph
        visible: cap.icon !== ""
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        name: cap.icon
        size: 16
        color: cap.ink
        opacity: cap.dim
    }
    Text {
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            leftMargin: glyph.visible ? glyph.x + glyph.width + 16 : 16
            right: row.left
            rightMargin: 8
        }
        text: cap.title
        elide: Text.ElideRight
        color: cap.ink
        opacity: cap.dim
        font.family: Theme.tok("font.title", "") || Theme.fam(cap.title, Theme.families)
        font.pixelSize: Theme.decor("title.size", 0) > 0 ? Theme.decor("title.size", 0) : 12
        font.weight: Theme.decor("title.weight", 400)
    }
    Row {
        id: row
        anchors.right: parent.right
        Repeater {
            model: cap.ids
            Item {
                id: b
                required property string modelData
                required property int index
                readonly property bool isClose: modelData === "close"
                readonly property bool down: hit.pressed && hit.containsMouse
                readonly property bool hot: hit.containsMouse
                readonly property bool last: index === cap.ids.length - 1
                readonly property color mark: isClose && (hot || down) ? "#ffffff" : cap.ink
                width: cap.bw
                height: cap.bh
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr(cap.actions[modelData] === "app_menu" ? "styles.title.app_menu"
                    : modelData === "maximize" && cap.full ? "styles.title.restore" : "styles.title." + modelData)
                Accessible.onPressAction: cap.act(modelData)
                Rectangle {
                    anchors.fill: parent
                    topRightRadius: b.last ? cap.r : 0
                    visible: b.hot || b.down
                    color: b.isClose ? (b.down ? Qt.alpha(cap.closeRed, 0.9) : cap.closeRed)
                        : cap.dark ? Qt.rgba(1, 1, 1, b.down ? 0.04 : 0.06) : Qt.rgba(0, 0, 0, b.down ? 0.024 : 0.039)
                }
                // The 10 px glyph, 1 px lines, centred (Segoe Fluent Icons' chrome glyphs).
                Shape {
                    id: g
                    readonly property real s: 10
                    readonly property real o: 0.5
                    x: Math.round((b.width - s) / 2)
                    y: Math.round((b.height - s) / 2)
                    width: s
                    height: s
                    opacity: b.hot || b.down ? 1 : cap.dim
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: b.mark
                        strokeWidth: cap.hair
                        fillColor: "transparent"
                        capStyle: ShapePath.FlatCap
                        joinStyle: ShapePath.MiterJoin
                        PathSvg {
                            path: {
                                var s = g.s, o = g.o
                                switch (b.modelData) {
                                case "close": return "M 0 0 L " + s + " " + s + " M " + s + " 0 L 0 " + s
                                case "minimize": return "M 0 " + (s / 2 + o) + " L " + s + " " + (s / 2 + o)
                                case "maximize":
                                    if (cap.full)
                                        return "M " + o + " " + (2 + o) + " h 7 v 7.5 h -7 Z M " + (2 + o) + " " + (2 + o)
                                            + " V " + o + " h 7.5 v 7 h -" + (2 - o)
                                    return "M " + o + " " + o + " h " + (s - 1) + " v " + (s - 1) + " h -" + (s - 1) + " Z"
                                default: return ""
                                }
                            }
                        }
                    }
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
