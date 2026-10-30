import QtQuick
import "../../core"
import ".."
import "../island"

// clock: `HH:MM · Fri` from svc.clock. On a side bar the glyph alone: the time is the bar's own clock, and the
// full line is the column's accessible name.
FaceBase {
    id: f
    readonly property var d: Store.docs["svc.clock"] || ({})
    readonly property string full: (f.d.hh ?? "--") + ":" + (f.d.mm ?? "--") + " · " + (f.d.weekday ?? "")
    Watch { doc: "svc.clock"; active: f.live }
    wantW: label.implicitWidth
    wantH: col.implicitHeight
    // The time flips digit by digit when the minute turns (W21, Capsule's idle flip clock); the weekday stays still. One
    // flip per minute, driven by svc.clock, no timer of its own (Ma).
    Row {
        id: label
        visible: !f.vertical
        anchors.centerIn: parent
        Accessible.role: Accessible.StaticText
        Accessible.name: f.full
        FlipText {
            anchors.verticalCenter: parent.verticalCenter
            text: (f.d.hh ?? "--") + ":" + (f.d.mm ?? "--")
            weight: Theme.wMedium
            animate: f.animate && f.live
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            anchors.verticalCenter: parent.verticalCenter
            Accessible.ignored: true
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: " · " + (f.d.weekday ?? "")
        }
    }
    Column {
        id: col
        visible: f.vertical
        anchors.centerIn: parent
        Accessible.role: Accessible.StaticText
        Accessible.name: f.full
        Icon {
            Accessible.ignored: true
            name: "schedule"
            glyph: "◷"
            size: Theme.fs + 4
        }
    }
}
