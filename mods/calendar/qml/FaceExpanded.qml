import QtQuick
import qs.core
import qs.components
import qs.components.faces
import "Calendar.js" as C

// Expanded view of the calendar peek: the coming event with its time, place and calendar, and the rest of today.
FaceBase {
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n
    id: f
    current: true

    readonly property var d: Store.docs["mod.calendar"] || ({})
    Watch { doc: "mod.calendar"; active: f.live }
    // The moment it is made: a peek lives seconds, the expanded view while it is open.
    property real nowS: Date.now() / 1000
    readonly property string todayKey: d.today || C.key(new Date())
    readonly property var list: C.upcoming(d, nowS, todayKey).slice(0, 4)
    readonly property var ev: list.length > 0 ? list[0] : null

    wantW: Math.max(col.implicitWidth, 280)
    implicitHeight: col.implicitHeight

    Column {
        id: col
        anchors.centerIn: parent
        spacing: Theme.xs
        Text {
            visible: f.ev !== null
            textFormat: Text.PlainText
            text: f.ev ? (f.ev.title || I18n.tr("mod-calendar.untitled")) : I18n.tr("mod-calendar.nothing_else")
            color: Theme.fg
            font.pixelSize: Theme.fsTitle
            font.weight: Theme.wBold
            font.family: Theme.fam(text, Theme.families)
        }
        Text {
            visible: f.ev !== null
            textFormat: Text.PlainText
            text: f.ev ? C.relative(I18n.tr, f.ev, f.nowS, f.todayKey, Qt.locale()) + "  ·  " + C.hm(f.ev.start)
                + (f.ev.end > f.ev.start ? "–" + C.hm(f.ev.end) : "")
                + (f.ev.location ? "  ·  " + f.ev.location : "") : ""
            color: Theme.accent
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }
        Repeater {
            model: f.list.slice(1)
            delegate: Text {
                required property var modelData
                textFormat: Text.PlainText
                text: C.hm(modelData.start) + "  " + (modelData.title || I18n.tr("mod-calendar.untitled"))
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
            }
        }
    }
}
