import QtQuick
import "../../../core"
import "../.."
import ".."

// Header (W53.6): a caption as a game menu's header band — NieR:Automata's (a parchment band, a square bullet, the title
// in capitals, the thick-and-thin rule under it), Dark Souls' (no band, a serif title over a gold hairline that fades at
// its ends) and Hollow Knight's (the title centred over an ornament rule) — drawn from the look's `[decor]` alone so any
// look can use it (rule 4): the band `title.fill` (one role solid, two a gradient; [] = none, the card's own ground),
// `title.mark` before the title (Bullet.qml), `title.caps` (capitals, wide tracking), `title.align`, `title.family`
// (`font.title`) at `title.size`/`title.weight` in `title.on` (`title.on_inactive` without focus), and `title.rule` in
// `title.rule_color` along the band's foot. The buttons sit on `title.buttons`' side, `title.inset` px in, each drawn as
// `title.close` says: a bare glyph (`glyph`), a solid square of the title's ink with the band's colour as its mark
// (`plate`: NieR's inverted keys) or a dot. Only buttons that act are drawn (TitleBase). Static (0 frames idle).
TitleBase {
    id: cap
    property bool full: false

    readonly property var fills: Theme.decor(active ? "title.fill" : "title.fill_inactive", [])
    readonly property bool banded: fills.length > 0
    readonly property color from: banded ? fills[0] : "transparent"
    readonly property color to: fills.length > 1 ? fills[1] : from
    readonly property string inkActive: Theme.decor("title.on", "")
    readonly property string inkInactive: Theme.decor("title.on_inactive", "")
    readonly property color ink: !active && inkInactive !== "" ? inkInactive : inkActive !== "" ? inkActive : Theme.fg
    readonly property string ruleRole: Theme.decor("title.rule_color", "")
    readonly property color ruleInk: ruleRole !== "" ? ruleRole : ink
    readonly property string face: Theme.decor("title.close", "glyph")
    readonly property bool startSide: Theme.decor("title.buttons", "end") === "start"
    readonly property bool centred: Theme.decor("title.align", "start") === "center"
    readonly property bool caps: Theme.decor("title.caps", false) === true
    readonly property string mark: Theme.decor("title.mark", "none")
    readonly property int inset: Theme.decor("title.inset", -1) >= 0 ? Theme.decor("title.inset", -1) : 10
    readonly property int gap: Theme.decor("title.button_gap", -1) >= 0 ? Theme.decor("title.button_gap", -1) : 4
    readonly property int btn: Theme.decor("title.button_w", 0) > 0 ? Theme.decor("title.button_w", 0)
                               : Math.max(12, Math.round((height - rule.height) * 0.62))
    readonly property real band: height - rule.height
    // The buttons, nearest the edge first: close, then the caller's.
    readonly property var names: (canClose ? ["close"] : []).concat(buttons || [])
    readonly property real btnRow: names.length > 0 ? inset + names.length * btn + (names.length - 1) * gap + 8 : inset

    Rectangle {
        visible: cap.banded
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: cap.band
        topLeftRadius: Math.max(0, Theme.decor("title.radius", -1))
        topRightRadius: topLeftRadius
        gradient: Gradient {
            orientation: Theme.decor("title.fill_dir", "horizontal") === "vertical" ? Gradient.Vertical : Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(cap.from, Theme.tok("color.surface_alpha", 1)) }
            GradientStop { position: 1; color: Qt.alpha(cap.to, Theme.tok("color.surface_alpha", 1)) }
        }
        Pattern { anchors.fill: parent }
    }
    Rule {
        id: rule
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                  leftMargin: kind === "filigree" ? 0 : cap.inset; rightMargin: kind === "filigree" ? 0 : cap.inset }
        kind: Theme.decor("title.rule", "none")
        ink: cap.ruleInk
        fade: kind === "single"
    }

    Row {
        id: label
        spacing: Math.round(cap.band * 0.3)
        y: Math.round((cap.band - height) / 2)
        x: cap.centred ? Math.round((cap.width - width) / 2)
           : (cap.startSide ? cap.btnRow : cap.inset)
        readonly property real room: cap.width - cap.btnRow - (cap.centred ? cap.btnRow : cap.inset)
        Bullet {
            id: bullet
            anchors.verticalCenter: parent.verticalCenter
            kind: cap.mark
            ink: cap.ink
            size: Math.max(5, Math.round(cap.band * 0.28))
        }
        Text {
            id: txt
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, Math.min(implicitWidth, label.room - (bullet.visible ? bullet.width + label.spacing : 0)))
            text: cap.caps ? cap.title.toUpperCase() : cap.title
            color: cap.ink
            elide: Text.ElideRight
            font.family: Theme.tok("font.title", "") || Theme.fam(cap.title, Theme.families)
            font.pixelSize: Theme.decor("title.size", 0) > 0 ? Theme.decor("title.size", 0) : Theme.fs
            font.weight: Theme.decor("title.weight", 700)
            font.letterSpacing: cap.caps ? Math.round(font.pixelSize * 0.12) : 0
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        }
    }

    Row {
        id: keys
        y: Math.round((cap.band - cap.btn) / 2)
        x: cap.startSide ? cap.inset : cap.width - cap.inset - width
        layoutDirection: cap.startSide ? Qt.LeftToRight : Qt.RightToLeft
        spacing: cap.gap
        Repeater {
            model: cap.names
            Item {
                id: b
                required property string modelData
                width: cap.btn
                height: cap.btn
                readonly property string kind: modelData === "close" ? "close"
                    : modelData === "maximize" ? (cap.full ? "restore" : "maximize") : "minimize"
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("decor.title." + modelData)
                Rectangle {
                    anchors.fill: parent
                    visible: cap.face === "plate" || cap.face === "dot"
                    radius: cap.face === "dot" ? width / 2 : 0
                    antialiasing: cap.face === "dot"
                    color: hit.pressed ? Qt.darker(cap.ink, 1.3) : cap.ink
                }
                CaptionGlyph {
                    anchors.centerIn: parent
                    visible: cap.face !== "dot" || hit.containsMouse
                    kind: b.kind
                    size: Math.round(cap.btn * (cap.face === "glyph" ? 0.62 : 0.5))
                    stroke: Math.max(1, Math.round(cap.btn / 9))
                    ink: cap.face === "glyph" ? cap.ink : (cap.banded ? cap.from : Theme.surface)
                }
                MouseArea {
                    id: hit
                    anchors.fill: parent
                    hoverEnabled: cap.face === "dot"
                    onClicked: b.modelData === "close" ? cap.close() : cap.button(b.modelData)
                }
            }
        }
    }
}
