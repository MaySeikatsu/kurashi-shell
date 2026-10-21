import QtQuick
import qs.core
import qs.components.faces
import "Calendar.js" as C

// Island face of the calendar mod: the peek before an event (setting `peek`; docs/ux/calendar.md "Views"). The daemon's
// job raises it `peek_minutes` before each timed event; this shows the event that comes next and when.
FaceBase {
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n
    id: f
    // A mod's face is loaded only while it is the Island's face (ModLoader), so it is current from its first frame.
    current: true

    readonly property var d: Store.docs["mod.calendar"] || ({})
    Watch { doc: "mod.calendar"; active: f.live }
    // The moment it is made: a peek lives seconds, the expanded view while it is open.
    property real nowS: Date.now() / 1000
    readonly property var ev: C.next(d, nowS, d.today || C.key(new Date()), 3 * 3600)

    wantW: row.implicitWidth
    Accessible.role: Accessible.StaticText
    Accessible.name: ev ? (ev.title || I18n.tr("mod-calendar.untitled")) + ", "
        + C.relative(I18n.tr, ev, nowS, d.today || "", Qt.locale()) : ""

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.gap
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 4
            height: Theme.fs + 4
            radius: 2
            color: f.ev ? (f.ev.color || Theme.accent) : Theme.accent
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: f.ev !== null
            textFormat: Text.PlainText
            text: f.ev ? (f.ev.title || I18n.tr("mod-calendar.untitled")) + " · "
                + C.relative(I18n.tr, f.ev, f.nowS, f.d.today || "", Qt.locale()) : ""
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
        }
    }
}
