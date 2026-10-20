import QtQuick
import "../../core"
import ".."

// A level as a row (W13; W21: a thick pill, SekaiPop's slider row): an icon, the Slider, and a readout (a percent, or a
// word such as "Muted"), on one Block. The slider follows the daemon's value, and `moved(v)` is the caller's intent.
// `unavailable`: no slider, the icon dimmed, nothing to act on.
Item {
    id: lv
    implicitHeight: Theme.controlH + 10 + Theme.shadowDy
    property string glyph: ""
    property string icon: ""            // a Material Symbols name (Icon.qml); `glyph` without the font
    property real value: 0              // 0..1, the value in effect
    property string readout: ""
    property bool unavailable: false
    property string a11y: ""
    signal moved(real v)

    Block {
        id: pill
        anchors.fill: parent
        radius: Theme.rFull
        fill: Theme.containerHigh
        readonly property real innerW: width - 2 * inset
        readonly property real innerH: faceH - 2 * inset

        Icon {
            id: mark
            x: 10
            width: 22
            height: pill.innerH
            name: lv.icon
            glyph: lv.glyph
            filled: !lv.unavailable
            size: 18
            color: lv.unavailable ? Theme.dim : Theme.accent
        }
        Slider {
            id: bar
            x: mark.x + mark.width + Theme.gap
            width: pill.innerW - x - readoutText.width - 14
            height: pill.innerH
            value: lv.value
            unavailable: lv.unavailable
            a11y: lv.a11y
            onMoved: v => lv.moved(v)
        }
        Text {
            id: readoutText
            x: pill.innerW - width - 14
            width: 64
            height: pill.innerH
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            color: lv.unavailable ? Theme.dim : Theme.fg
            font.pixelSize: Theme.fsLabel
            font.weight: Theme.wBold
            font.family: Theme.fam(text, Theme.families)
            text: lv.readout
        }
    }
}
