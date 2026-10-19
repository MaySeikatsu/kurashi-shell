import QtQuick
import "../../core"

// clock: `HH:MM · Fri` from svc.clock. On a side bar the glyph alone: the time is the bar's own clock, and the
// full line is the column's accessible name.
FaceBase {
    id: f
    readonly property var d: Store.docs["svc.clock"] || ({})
    readonly property string full: (f.d.hh ?? "--") + ":" + (f.d.mm ?? "--") + " · " + (f.d.weekday ?? "")
    Watch { doc: "svc.clock"; active: f.live }
    wantW: label.implicitWidth
    wantH: col.implicitHeight
    Text {
        id: label
        visible: !f.vertical
        anchors.centerIn: parent
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: f.full
    }
    Column {
        id: col
        visible: f.vertical
        anchors.centerIn: parent
        Accessible.role: Accessible.StaticText
        Accessible.name: f.full
        Text {
            Accessible.ignored: true
            color: Theme.fg
            font.pixelSize: Theme.fs
            text: "◷"
        }
    }
}
