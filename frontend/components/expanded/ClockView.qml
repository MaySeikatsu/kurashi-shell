import QtQuick
import "../../core"

// The expanded view of the clock face (K24): today's date and a month grid, Monday first, today in
// the accent. The grid is built from svc.clock.date, the day the daemon means, so the view is
// presentation only. Watches svc.clock only while it is on screen (Ma).
Column {
    id: view
    width: parent.width
    spacing: Theme.gap

    Watch { doc: "svc.clock" }
    readonly property var d: Store.docs["svc.clock"] || ({})
    // YYYY-MM-DD in the local zone. Anything else shows no grid rather than a guessed one.
    readonly property var ymd: /^\d{4}-\d{2}-\d{2}$/.test(d.date ?? "") ? String(d.date).split("-").map(Number) : []
    readonly property bool valid: ymd.length === 3
    readonly property int year: valid ? ymd[0] : 0
    readonly property int month: valid ? ymd[1] : 1         // 1..12
    readonly property int today: valid ? ymd[2] : 0
    readonly property date first: new Date(year, month - 1, 1)
    readonly property int lead: (first.getDay() + 6) % 7    // cells before day 1, Monday first
    readonly property int count: valid ? new Date(year, month, 0).getDate() : 0
    readonly property int cell: 36

    Text {
        width: view.width
        color: Theme.fg
        font.pixelSize: Theme.fsTitle
        font.family: Theme.fam(text, Theme.families)
        text: view.valid ? Qt.locale().toString(new Date(view.year, view.month - 1, view.today), "dddd, d MMMM yyyy") : ""
    }
    Text {
        width: view.width
        color: Theme.dim
        font.pixelSize: Theme.fsLabel
        font.family: Theme.fam(text, Theme.families)
        text: view.valid ? Qt.locale().toString(view.first, "MMMM yyyy") : ""
    }
    Item {
        width: view.width
        height: grid.height
        Grid {
            id: grid
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 7
            Repeater {
                model: 7
                delegate: Text {
                    required property int index
                    width: view.cell
                    height: view.cell / 2
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    // Qt.DayOfWeek: Monday is 1.
                    text: Qt.locale().standaloneDayName(index + 1, Locale.ShortFormat)
                }
            }
            Repeater {
                model: view.valid ? 42 : 0
                delegate: Rectangle {
                    required property int index
                    readonly property int day: index - view.lead + 1
                    readonly property bool inMonth: day >= 1 && day <= view.count
                    readonly property bool isToday: inMonth && day === view.today
                    width: view.cell
                    height: view.cell
                    radius: Theme.rFull
                    color: isToday ? Theme.accent : "transparent"
                    Text {
                        anchors.centerIn: parent
                        visible: parent.inMonth
                        color: parent.isToday ? Theme.fgOnAccent : Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: parent.day
                    }
                }
            }
        }
    }
}
