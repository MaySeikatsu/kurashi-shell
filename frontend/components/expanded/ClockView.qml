import QtQuick
import "../../core"
import ".."
import "../island"

// The expanded view of the clock face (K24; island brief 5): the selected day's date, the month grid with today in the
// accent, the selected day's agenda (the clock.expanded.day slot, with its reason while no calendar contributes), the
// weather aside (clock.expanded.aside) and the footer slot (clock.expanded.footer). Keyboard on the grid: the arrows move
// the selected day (Up and Down a week), PageUp and PageDown a month, Home goes to today. Dates are written in kurashi's
// language, the i18n document's locale (ja, else English, the daemon's fallback), not the system's (B19).
// W19 (rows 71, 72; I46): the weeks start on `clock.week_start` (auto: Sunday for ja, Monday otherwise), and the grid shows
// ISO week numbers when `clock.week_numbers` is on. Each day cell hosts the `clock.expanded.daymark` contributions (three
// at most, side by side under the number, each given the cell's `date`); with none, no object is made.
// The grid is built from svc.clock.date, the day the daemon means. Watches svc.clock and config only while on screen (Ma).
Column {
    id: view
    width: parent.width
    spacing: Theme.gap

    Watch { doc: "svc.clock" }
    Watch { doc: "config" }
    readonly property var d: Store.docs["svc.clock"] || ({})
    readonly property string lang: (Store.docs["i18n"] || ({})).locale === "ja" ? "ja" : "en"
    readonly property var loc: Qt.locale(lang)
    readonly property string headerFmt: lang === "ja" ? "yyyy年M月d日（dddd）" : "dddd, d MMMM yyyy"
    readonly property string monthFmt: lang === "ja" ? "yyyy年M月" : "MMMM yyyy"
    readonly property string agendaFmt: lang === "ja" ? "M月d日（ddd）" : "ddd d MMM"

    // A value the daemon serves in `config` (`values[key].value`, with its provenance beside it); undefined until it does.
    function configValue(key) {
        var c = Store.docs["config"]
        var p = c && c.values ? c.values[key] : undefined
        return p ? p.value : undefined
    }
    // The first day of the week, as JS numbers it (0 Sunday .. 6 Saturday). auto, or a value this build does not know:
    // Sunday for Japanese, Monday otherwise (the schema's own text for the key).
    readonly property int firstDow: {
        var w = configValue("clock.week_start")
        if (w === "sunday") return 0
        if (w === "monday") return 1
        if (w === "saturday") return 6
        return lang === "ja" ? 0 : 1
    }
    readonly property bool weekNumbers: configValue("clock.week_numbers") === true
    readonly property int weekW: weekNumbers ? 26 : 0      // the week-number column and its gap, left of the grid

    // YYYY-MM-DD in the local zone. Anything else shows no grid rather than a guessed one.
    readonly property var ymd: /^\d{4}-\d{2}-\d{2}$/.test(d.date ?? "") ? String(d.date).split("-").map(Number) : []
    readonly property bool valid: ymd.length === 3
    readonly property date today: valid ? new Date(ymd[0], ymd[1] - 1, ymd[2]) : new Date(0)
    // The selected day; the grid shows its month. Starts on today.
    property date sel: today
    readonly property int year: sel.getFullYear()
    readonly property int month: sel.getMonth()             // 0..11
    // The selected day as yyyy-mm-dd: the `date` the agenda slot is given (CONTRACT-CHANGE row 200), empty when not valid.
    readonly property string selIso: valid ? isoDate(year, month, sel.getDate()) : ""
    readonly property date first: new Date(year, month, 1)
    readonly property int lead: (first.getDay() - firstDow + 7) % 7     // cells before day 1, counted from the week's first day
    readonly property int count: new Date(year, month + 1, 0).getDate()
    // The grid's weeks: five for most months, six when the month reaches a sixth row (I203: no empty row above the agenda).
    // Synchronous from the props, so the grid's box has its final height before its cells are made (B37).
    readonly property int weeks: valid ? Math.ceil((lead + count) / 7) : 0
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
    // YYYY-MM-DD of a day: the `date` a day mark is given.
    function isoDate(y, m, d) {
        return y + "-" + (m < 9 ? "0" : "") + (m + 1) + "-" + (d < 10 ? "0" : "") + d
    }
    // ISO 8601 week number of grid row `row` (0..5): the week of the row's Thursday, which lies in the row whatever day
    // the weeks start on, so a Sunday-first row and a Monday-first row number alike.
    function isoWeekOfRow(row) {
        var start = new Date(year, month, 1 - lead + row * 7)
        var thu = new Date(start.getFullYear(), start.getMonth(), start.getDate() + (4 - start.getDay() + 7) % 7)
        var y = thu.getFullYear()
        var days = Math.round((Date.UTC(y, thu.getMonth(), thu.getDate()) - Date.UTC(y, 0, 1)) / 86400000)
        return Math.floor(days / 7) + 1
    }

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
        KeyButton {
            id: prevMonth
            side: 28
            iconSize: Theme.fs + 6
            icon: "chevron_left"
            glyph: "‹"
            a11y: I18n.tr("island.clock.prev_month")
            enabled: view.valid
            onClicked: view.shiftMonths(-1)
        }
        Text {
            width: view.width - prevMonth.width - nextMonth.width - todayBtn.width - 3 * Theme.gap
            height: prevMonth.height
            font.weight: Theme.wMedium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: Theme.fg
            font.pixelSize: Theme.fsLabel
            font.family: Theme.fam(text, Theme.families)
            text: view.valid ? view.loc.toString(view.first, view.monthFmt) : ""
        }
        KeyButton {
            id: nextMonth
            side: 28
            iconSize: Theme.fs + 6
            icon: "chevron_right"
            glyph: "›"
            a11y: I18n.tr("island.clock.next_month")
            enabled: view.valid
            onClicked: view.shiftMonths(1)
        }
        KeyButton {
            id: todayBtn
            side: 28
            primary: true
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
        // The box clips the grid and the week numbers while the grid eases to its height (I203).
        clip: true
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
            default: event.accepted = false; return    // Escape and the rest go on to the card (the Stage closes on Escape)
            }
            event.accepted = true
        }
        // The day marks' contributions (row 71). The host draws none itself: each day cell below places one ModLoader
        // per contribution, so this host only lists them.
        SlotHost { id: marks; slot: "clock.expanded.daymark"; layout: "cells" }
        // B37 (W35): the 42 day cells, a Block each, took ~65 ms to make, all of it before the island's first frame (the
        // view is made when the card opens). They are made asynchronously in a box of their final size: the card has its
        // height at once, so the shape grows straight to it, and the cells are there before the view fades in.
        Loader {
            id: grid
            x: Math.round((cal.width - view.weekW - width) / 2 + view.weekW)
            width: 7 * view.cell
            height: view.cell / 2 + view.weeks * view.cell
            asynchronous: true
            // I203: the sixth row comes and goes with the month. The box eases to its new height, so the agenda below it (and the
            // card, which follows the view's height) glide instead of jumping. Off while the card is away or the month not dated.
            Behavior on height {
                enabled: view.visible && view.valid && Theme.springOn
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
            }
            sourceComponent: Grid {
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
                        // Column 0 is the week's first day. Qt numbers Monday 1 to Sunday 7, JS numbers Sunday 0.
                        text: {
                            var dow = (view.firstDow + index) % 7
                            return view.loc.standaloneDayName(dow === 0 ? 7 : dow, Locale.ShortFormat)
                        }
                    }
                }
                Repeater {
                    model: view.weeks * 7
                    // W21: each day is a small block (a keycap under keycap chrome); today is lit in the accent, the selected
                    // day is tonal (Theme.selected) and ringed while the grid has the keyboard.
                    delegate: Item {
                        id: dayCell
                        required property int index
                        readonly property int day: index - view.lead + 1
                        readonly property bool inMonth: day >= 1 && day <= view.count
                        readonly property bool isToday: inMonth && view.todayInView && day === view.todayDay
                        readonly property bool isSel: inMonth && day === view.sel.getDate()
                        // The cell's date (yyyy-mm-dd) for the day marks; empty outside the month.
                        readonly property string iso: inMonth ? view.isoDate(view.year, view.month, day) : ""
                        // The keycap's face (Block.face: the block less its hard shadow; a press sinks it, and the number and the
                        // marks sink with it) and the middle of the band above the day mark (I203). The mark is a 5 px dot centred
                        // in its row, the row's foot on the face's foot; with no mark the number is centred on the face.
                        readonly property real faceTop: dayBlock.y + dayBlock.face.y
                        readonly property real faceBot: faceTop + dayBlock.face.height
                        readonly property real dotTop: marksRow.height > 0 ? faceBot - (marksRow.height + 5) / 2 : faceBot
                        readonly property real numberMid: (faceTop + dotTop) / 2
                        width: view.cell
                        height: view.cell
                        Accessible.role: Accessible.Cell
                        Accessible.name: inMonth ? view.loc.toString(new Date(view.year, view.month, day), view.headerFmt) : ""
                        Block {
                            id: dayBlock
                            visible: dayCell.inMonth
                            // A grid of 31 keys: no soft shadow each (the card has one).
                            softScale: 0
                            x: 2
                            y: 2 - Math.round(Theme.shadowDy / 2)
                            width: parent.width - 4
                            height: parent.height - 4
                            radius: Theme.rSm + 2
                            ringScale: 0
                            animate: view.visible
                            fill: dayCell.isToday ? Theme.accent : (dayCell.isSel ? Theme.selected : Theme.containerHigh)
                            flatBorder: dayCell.isSel && !dayCell.isToday ? Qt.alpha(Theme.fg, 0.25) : "transparent"
                            pressed: dayTap.pressed
                        }
                        FocusRing {
                            anchors.fill: dayBlock
                            anchors.bottomMargin: Theme.shadowDy
                            anchors.margins: -1
                            shown: dayCell.isSel && cal.activeFocus
                            corner: Theme.rSm + 3
                        }
                        Text {
                            anchors.centerIn: dayBlock
                            anchors.verticalCenterOffset: dayCell.numberMid - (dayBlock.y + dayBlock.height / 2)
                            visible: parent.inMonth
                            color: parent.isToday ? Theme.fgOnAccent
                                : (parent.isSel ? Theme.fgOnSelected : Theme.fg)
                            font.pixelSize: Theme.fs
                            font.weight: parent.isToday || parent.isSel ? Theme.wBold : Theme.wRegular
                            font.family: Theme.fam(text, Theme.families)
                            font.features: { "tnum": 1 }
                            text: parent.day
                        }
                        // The day marks (row 71): one ModLoader per contribution, three at most, side by side under the number, on the
                        // keycap's foot (I203). Each gets the cell's date; a cell outside the month gets none.
                        Row {
                            id: marksRow
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: dayCell.faceBot - height
                            spacing: 2
                            Repeater {
                                model: dayCell.inMonth ? marks.entries.slice(0, 3) : []
                                delegate: ModLoader {
                                    required property var modelData
                                    url: modelData.qml
                                    extra: ({ date: dayCell.iso })
                                }
                            }
                        }
                        MouseArea {
                            id: dayTap
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
        // ISO week numbers beside the rows (W19, I46), when clock.week_numbers is on. Not focus stops: the grid's keys do it.
        Repeater {
            model: view.weekNumbers ? view.weeks : 0
            delegate: Text {
                required property int index
                readonly property string week: String(view.isoWeekOfRow(index))
                x: grid.x - view.weekW
                y: grid.y + view.cell / 2 + index * view.cell
                width: view.weekW - Theme.xs
                height: view.cell
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: week
                Accessible.role: Accessible.StaticText
                Accessible.name: I18n.tr("frontend.clock.week_n").replace("{n}", week)
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
        SlotHost { id: agendaHost; slot: "clock.expanded.day"; width: parent.width; extra: ({ date: view.selIso }) }
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
