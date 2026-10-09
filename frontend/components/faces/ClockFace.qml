import QtQuick
import "../../core"

// clock: `HH:MM · Fri` from svc.clock.
FaceBase {
    id: f
    readonly property var d: Store.docs["svc.clock"] || ({})
    Watch { doc: "svc.clock"; active: f.live }
    wantW: label.implicitWidth
    Text {
        id: label
        anchors.centerIn: parent
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: (f.d.hh ?? "--") + ":" + (f.d.mm ?? "--") + " · " + (f.d.weekday ?? "")
    }
}
