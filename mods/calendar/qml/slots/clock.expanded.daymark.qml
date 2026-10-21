import QtQuick
import qs.core

// Day mark (K28 slot `clock.expanded.daymark`, row 71; docs/ux/calendar.md "Views"): a dot under the number of each day
// that has events, in the colour of its first event's calendar (the text colour when it has none), and nothing for
// a day without. GNOME's and KDE's month grids do the same. The host gives `date` (yyyy-mm-dd) on each load and change.
Item {
    id: mark
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n
    property string date: ""

    property bool live: visible
    Watch { doc: "mod.calendar"; active: mark.live }

    readonly property var d: Store.docs["mod.calendar"] || ({})
    readonly property var list: (d.days && date !== "" && d.days[date]) || []
    readonly property bool has: list.length > 0

    implicitWidth: has ? 8 : 0
    implicitHeight: 14
    Accessible.role: Accessible.StaticText
    Accessible.name: has ? I18n.tr("mod-calendar.a11y.has_events").replace("{n}", list.length) : ""

    Rectangle {
        visible: mark.has
        anchors.centerIn: parent
        width: 5
        height: 5
        radius: 2.5
        color: mark.has ? (mark.list[0].color || Theme.fg) : "transparent"
    }
}
