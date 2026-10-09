import QtQuick
import "../../core"
import ".."

// A level as a row (W13): a glyph, the Slider, and a readout (a percent, or a word such as "Muted"). The slider follows the
// daemon's value, and `moved(v)` is the caller's intent. `unavailable`: no slider, the glyph dimmed, nothing to act on.
Item {
    id: lv
    implicitHeight: Theme.controlH
    property string glyph: ""
    property real value: 0              // 0..1, the value in effect
    property string readout: ""
    property bool unavailable: false
    property string a11y: ""
    signal moved(real v)

    Text {
        id: mark
        width: 20
        height: parent.height
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: lv.unavailable ? Theme.dim : Theme.accent
        font.pixelSize: Theme.fs + 2
        font.family: Theme.fam(text, Theme.families)
        text: lv.glyph
    }
    Slider {
        id: bar
        x: mark.width + Theme.gap
        width: lv.width - x - readoutText.width - 2 * Theme.gap
        height: Theme.controlH
        value: lv.value
        unavailable: lv.unavailable
        a11y: lv.a11y
        onMoved: v => lv.moved(v)
    }
    Text {
        id: readoutText
        anchors.right: parent.right
        width: 72
        height: parent.height
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        color: lv.unavailable ? Theme.dim : Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: lv.readout
    }
}
