import QtQuick
import "../../core"
import ".."

// The expanded view of the clock face (K24; island brief 5): the selected day's date, the month grid with today in the
// accent, the selected day's agenda (the clock.expanded.day slot, with its reason while no calendar contributes), the
// weather aside (clock.expanded.aside) and the footer slot (clock.expanded.footer). Keyboard on the grid: the arrows move
// the selected day (Up and Down a week), PageUp and PageDown a month, Home goes to today. Dates are written in kurashi's
// language, the i18n document's locale (ja, else English, the daemon's fallback), not the system's (B19). Weeks start on
// Monday. The grid is built from svc.clock.date, the day the daemon means. Watches svc.clock only while on screen (Ma).
// Event dots need a per-day contract that the slots do not give yet, so none are drawn.
Column {
    id: view
    width: parent.width
    spacing: Theme.gap

    Watch { doc: "svc.clock" }
    readonly property var d: Store.docs["svc.clock"] || ({})
    readonly property string lang: (Store.docs["i18n"] || ({})).locale === "ja" ? "ja" : "en"
    readonly property var loc: Qt.locale(lang)
    readonly property string headerFmt: lang === "ja" ? "yyyy年M月d日（dddd）" : "dddd, d MMMM yyyy"
    readonly property string monthFmt: lang === "ja" ? "yyyy年M月" : "MMMM yyyy"
    readonly property string agendaFmt: lang === "ja" ? "M月d日（ddd）" : "ddd d MMM"

    // YYYY-MM-DD in the local zone. Anything else shows no grid rather than a guessed one.
    readonly property var ymd: /^\d{4}-\d{2}-\d{2}$/.test(d.date ?? "") ? String(d.date).split("-").map(Number) : []
    readonly property bool valid: ymd.length === 3
    readonly property date today: valid ? new Date(ymd[0], ymd[1] - 1, ymd[2]) : new Date(0)
    // The selected day; the grid shows its month. Starts on today.
    property date sel: today
    readonly property int year: sel.getFullYear()
    readonly property int month: sel.getMonth()             // 0..11
    readonly property date first: new Date(year, month, 1)
    readonly property int lead: (first.getDay() + 6) % 7     // cells before day 1, Monday first
    readonly property int count: new Date(year, month + 1, 0).getDate()
    readonly property bool todayInView: valid && today.getFullYear() === year && today.getMonth() === month
    readonly property int todayDay: today.getDate()
    readonly property int cell: 36

    function select(date) { sel = new Date(date.getFullYear(), date.getMonth(), date.getDate()) }
    function shiftDays(n) { select(new Date(sel.getFullYear(), sel.getMonth(), sel.getDate() + n)) }
    // The same day of the month in another month, or its last day when that month is shorter.
    function shiftMonths(n) {
        var y = sel.getFullYear(), m = sel.getMonth() + n
        var last = new Date(y, m + 1, 0).getDate()
        select(new Date(y, m, Math.min(sel.getDate(), last)))
    }
    function goToday() { if (valid) select(today) }

    Row {
        width: view.width
        spacing: Theme.gap
        Column {
            width: view.width - (aside.visible ? aside.width + Theme.gap : 0)
            spacing: Theme.xs
            Text {
                visible: view.valid
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                font.family: Theme.fam(text, Theme.families)
                text: view.valid ? view.loc.toString(view.sel, view.headerFmt) : ""
            }
            StaleNote { face: "clock" }
        }
        SlotHost { id: aside; slot: "clock.expanded.aside"; width: 140 }
    }

    Row {
        id: nav
        width: view.width
        spacing: Theme.gap
        IconButton {
            id: prevMonth
            glyph: "‹"
            a11y: I18n.tr("island.clock.prev_month")
            enabled: view.valid
            onClicked: view.shiftMonths(-1)
        }
        Text {
            width: view.width - prevMonth.width - nextMonth.width - todayBtn.width - 3 * Theme.gap
            height: Theme.controlH
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: Theme.fg
            font.pixelSize: Theme.fsLabel
            font.family: Theme.fam(text, Theme.families)
            text: view.valid ? view.loc.toString(view.first, view.monthFmt) : ""
        }
        IconButton {
            id: nextMonth
            glyph: "›"
            a11y: I18n.tr("island.clock.next_month")
            enabled: view.valid
            onClicked: view.shiftMonths(1)
        }
        Button {
            id: todayBtn
            label: I18n.tr("island.clock.today")
            enabled: view.valid
            onClicked: view.goToday()
        }
    }

    // The month grid is one focus stop (Tab). Its keys move the selected day; the selected day is the ring.
    Item {
        id: cal
        width: view.width
        height: grid.height
        activeFocusOnTab: view.valid
        Accessible.role: Accessible.Table
        Accessible.name: I18n.tr("island.clock.grid")
        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Left: view.shiftDays(-1); break
            case Qt.Key_Right: view.shiftDays(1); break
            case Qt.Key_Up: view.shiftDays(-7); break
            case Qt.Key_Down: view.shiftDays(7); break
            case Qt.Key_PageUp: view.shiftMonths(-1); break
            case Qt.Key_PageDown: view.shiftMonths(1); break
            case Qt.Key_Home: view.goToday(); break
            default: return
            }
            event.accepted = true
        }
        FocusRing { anchors.fill: grid; shown: cal.activeFocus; corner: Theme.rSm }
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
                    text: view.loc.standaloneDayName(index + 1, Locale.ShortFormat)
                }
            }
            Repeater {
                model: view.valid ? 42 : 0
                delegate: Rectangle {
                    required property int index
                    readonly property int day: index - view.lead + 1
                    readonly property bool inMonth: day >= 1 && day <= view.count
                    readonly property bool isToday: inMonth && view.todayInView && day === view.todayDay
                    readonly property bool isSel: inMonth && day === view.sel.getDate()
                    width: view.cell
                    height: view.cell
                    radius: Theme.rFull
                    color: isToday ? Theme.accent : "transparent"
                    border.width: isSel ? 2 : 0
                    border.color: cal.activeFocus ? Theme.focusRing : Theme.dim
                    Accessible.role: Accessible.Cell
                    Accessible.name: inMonth ? view.loc.toString(new Date(view.year, view.month, day), view.headerFmt) : ""
                    Text {
                        anchors.centerIn: parent
                        visible: parent.inMonth
                        color: parent.isToday ? Theme.fgOnAccent : Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: parent.day
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: parent.inMonth
                        onClicked: {
                            view.select(new Date(view.year, view.month, parent.day))
                            cal.forceActiveFocus()
                        }
                    }
                }
            }
        }
    }

    // The agenda of the selected day. The slot's contributions (a calendar mod) fill it; with none, the reason says why.
    Column {
        width: view.width
        spacing: Theme.xs
        Text {
            visible: view.valid
            width: parent.width
            color: Theme.dim
            font.pixelSize: Theme.fsLabel
            font.family: Theme.fam(text, Theme.families)
            text: view.valid ? I18n.tr("island.clock.agenda") + " · " + view.loc.toString(view.sel, view.agendaFmt) : ""
        }
        SlotHost { id: agendaHost; slot: "clock.expanded.day"; width: parent.width }
        Text {
            visible: agendaHost.entries.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("island.clock.agenda.none")
        }
    }
    SlotHost { slot: "clock.expanded.footer"; width: view.width }
}
