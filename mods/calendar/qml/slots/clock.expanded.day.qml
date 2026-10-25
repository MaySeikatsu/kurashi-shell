import QtQuick
import qs.core
import qs.components
import "../Calendar.js" as C

// The selected day's agenda in the clock card (K28 slot `clock.expanded.day`; docs/ux/calendar.md "Views"): up to six
// rows `colour bar · time · title · location`, all-day first, "+ N more"; on today the past rows are dimmed, the
// running one says "now" in the accent and a thin line marks the present. Under the rows, one line per source that is
// offline or failing (never silent). While no calendar is set the host hands `reason`: the call to action instead.
// The selected day is the host's `date` (yyyy-MM-dd, CONTRACT-CHANGE row 200; the clock card passes its selection), and
// today while none is given. A row is a button: a click, Return, Enter or Space turns the list into that event's details
// in the card (docs/ux/calendar.md "Event details"); Back, or Escape, returns to the list. Ma: the document is watched
// and the minute timer runs only while visible.
Item {
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n
    // The daemon's reason while this contribution needs setup (an i18n key); "" otherwise.
    property string reason: ""
    // The selected day (yyyy-MM-dd), when the host passes it.
    property string date: ""
    id: ag

    property bool live: visible
    Watch { doc: "mod.calendar"; active: ag.live }

    readonly property var d: Store.docs["mod.calendar"] || ({})
    // The host's reason, or the document's own "none" (the reason reaches runtime.slots once the service runs).
    readonly property bool needsSetup: reason !== "" || d.state === "none"
    readonly property bool loaded: d.state !== undefined
    readonly property string lang: (Store.docs["i18n"] || ({})).locale === "ja" ? "ja" : "en"
    readonly property var loc: Qt.locale(lang)
    readonly property string dayFmt: lang === "ja" ? "M月d日（ddd）" : "ddd d MMM"
    readonly property string todayKey: d.today || C.key(new Date())
    readonly property string day: date !== "" ? date : todayKey
    readonly property bool isToday: day === todayKey
    readonly property var all: C.events(d, day)
    readonly property int maxRows: 6
    readonly property var shown: all.slice(0, maxRows)
    readonly property var notes: C.notes(I18n.tr, d, nowS)

    property real nowS: Date.now() / 1000
    Timer {
        interval: 30000
        repeat: true
        running: ag.live && ag.isToday
        onTriggered: ag.nowS = Date.now() / 1000
    }
    onLiveChanged: nowS = Date.now() / 1000

    // The first row that has not started yet (today): the now-line sits above it.
    readonly property int nowIndex: {
        if (!isToday) return -1
        for (var i = 0; i < shown.length; i++) {
            if (!shown[i].all_day && shown[i].start > nowS) return i
        }
        return -1
    }

    // The event whose details the card shows: its row (`openIndex` in `shown`) and its id. A refresh that drops the
    // event closes them, and so does a change of day.
    property int openIndex: -1
    property string openId: ""
    readonly property var openEv: {
        if (openId === "") return null
        for (var i = 0; i < all.length; i++) {
            if (all[i].id === openId) return all[i]
        }
        return null
    }
    readonly property bool open: openEv !== null
    readonly property bool openRunning: open && isToday && C.isRunning(openEv, nowS)
    onOpenEvChanged: if (openEv === null) openId = ""
    onDayChanged: openId = ""

    // Row `i` of the list opens its details, and the Back button takes the focus.
    function openDetails(i) {
        if (i < 0 || i >= shown.length) return
        openIndex = i
        openId = shown[i].id
        back.forceActiveFocus()
    }
    // Back to the list, with the focus on the row that opened the details (when that row is still there).
    function closeDetails() {
        var i = openIndex
        var row = i >= 0 ? rows.itemAt(i) : null
        openId = ""
        openIndex = -1
        if (row) row.focusTarget.forceActiveFocus()
    }
    // Escape closes the details and nothing else: with the list up the event goes on, up to the card, which closes the
    // island. The handler says so both ways: a key event is taken unless a handler gives it back.
    Keys.onEscapePressed: event => {
        if (ag.open) {
            ag.closeDetails()
            event.accepted = true
        } else {
            event.accepted = false
        }
    }

    implicitHeight: open ? det.implicitHeight : col.implicitHeight
    implicitWidth: 320

    Column {
        id: col
        width: ag.width
        spacing: Theme.xs
        visible: !ag.open

        // ---- needs setup: no calendar is set ----
        Row {
            visible: ag.needsSetup
            width: parent.width
            spacing: Theme.gap
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - addBtn.width - Theme.gap
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("mod-calendar.no_source")
            }
            Button {
                id: addBtn
                label: I18n.tr("mod-calendar.add")
                icon: "add"
                onClicked: Store.act("settings.open", { key: "mods.calendar.sources" })
            }
        }

        // ---- loading, empty day ----
        Text {
            visible: !ag.needsSetup && (!ag.loaded || ag.d.state === "loading" || ag.all.length === 0)
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: !ag.loaded || ag.d.state === "loading" ? I18n.tr("mod-calendar.loading")
                : ag.d.state === "error" ? I18n.tr(ag.d.reason || "mod-calendar.error.all")
                : I18n.tr("mod-calendar.empty_day")
        }

        // ---- the rows: each one a button that opens the event's details ----
        Repeater {
            id: rows
            model: ag.needsSetup ? [] : ag.shown
            delegate: Column {
                id: row
                required property var modelData
                required property int index
                readonly property bool past: ag.isToday && C.isPast(modelData, ag.nowS)
                readonly property bool running: ag.isToday && C.isRunning(modelData, ag.nowS)
                property alias focusTarget: evRow
                width: col.width
                spacing: 2
                Rectangle {
                    visible: row.index === ag.nowIndex && row.index > 0
                    width: parent.width
                    height: 1
                    color: Theme.accent
                }
                Item {
                    id: evRow
                    width: parent.width
                    height: Math.max(title.implicitHeight, time.implicitHeight) + 4
                    opacity: row.past ? Theme.staleOpacity : 1
                    // Tab reaches a row; Return, Enter and Space, or a click, open its details.
                    activeFocusOnTab: true
                    Keys.onReturnPressed: ag.openDetails(row.index)
                    Keys.onEnterPressed: ag.openDetails(row.index)
                    Keys.onSpacePressed: ag.openDetails(row.index)
                    Accessible.role: Accessible.Button
                    Accessible.name: C.a11y(I18n.tr, row.modelData, ag.day) + (row.running ? ", " + I18n.tr("mod-calendar.now") : "")
                    Accessible.onPressAction: ag.openDetails(row.index)
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { evRow.forceActiveFocus(); ag.openDetails(row.index) }
                    }
                    FocusRing { anchors.fill: parent; shown: evRow.activeFocus; corner: Theme.rSm }
                    Rectangle {
                        id: bar
                        width: 3
                        height: parent.height - 4
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 1.5
                        color: row.modelData.color || Theme.accent
                    }
                    Text {
                        id: time
                        anchors.left: bar.right
                        anchors.leftMargin: Theme.gap
                        anchors.verticalCenter: parent.verticalCenter
                        width: 92
                        elide: Text.ElideRight
                        color: row.running ? Theme.accent : Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.weight: row.running ? Theme.wBold : Theme.wRegular
                        font.family: Theme.fam(text, Theme.families)
                        font.features: { "tnum": 1 }
                        text: row.running ? I18n.tr("mod-calendar.now") : C.timeLabel(I18n.tr, row.modelData, ag.day)
                    }
                    Text {
                        id: title
                        anchors.left: time.right
                        anchors.leftMargin: Theme.xs
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: (row.modelData.title || I18n.tr("mod-calendar.untitled"))
                            + (row.modelData.location ? "  ·  " + row.modelData.location : "")
                    }
                }
            }
        }
        Text {
            visible: !ag.needsSetup && ag.all.length > ag.maxRows
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: C.fill(I18n.tr("mod-calendar.more"), { n: ag.all.length - ag.maxRows })
        }

        // ---- sources that are offline or failing ----
        Repeater {
            model: ag.needsSetup ? [] : ag.notes
            delegate: Text {
                required property var modelData
                width: col.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                color: modelData.error ? Theme.error : Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: modelData.text
            }
        }
    }

    // ---- the event's details (docs/ux/calendar.md "Event details"): what it is, when, where, which calendar, its text ----
    Item {
        id: det
        readonly property var e: ag.openEv || ({})
        visible: ag.open
        width: ag.width
        implicitHeight: detCol.implicitHeight + 2 * Theme.gap
        height: implicitHeight
        Accessible.role: Accessible.Pane
        Accessible.name: ag.open ? C.fill(I18n.tr("mod-calendar.a11y.details"), { title: det.e.title || I18n.tr("mod-calendar.untitled") }) : ""

        Block {
            anchors.fill: parent
            softScale: 0
            ringScale: 0
            radius: Theme.rSm + 4
            fill: Theme.containerHigh
            flatBorder: Theme.outline     // a hairline under flat chrome (none); the outline role elsewhere
        }
        Column {
            id: detCol
            x: Theme.gap
            y: Theme.gap
            width: det.width - 2 * Theme.gap
            spacing: Theme.xs
            Button {
                id: back
                label: I18n.tr("mod-calendar.details.back")
                icon: "chevron_left"
                onClicked: ag.closeDetails()
            }
            // The calendar: its colour bar and name (the colour is never the only sign of it).
            Row {
                visible: !!det.e.calendar
                width: parent.width
                spacing: Theme.xs
                Rectangle {
                    width: 3
                    height: calName.implicitHeight
                    radius: 1.5
                    color: det.e.color || Theme.accent
                }
                Text {
                    id: calName
                    width: parent.width - 3 - Theme.xs
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: det.e.calendar || ""
                }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                text: det.e.title || I18n.tr("mod-calendar.untitled")
            }
            // The span: "Thu 14 Oct · 09:15–09:30", "All day", "Sat 2 Aug – Tue 5 Aug · All day"; "now" while it runs.
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                color: ag.openRunning ? Theme.accent : Theme.dim
                font.pixelSize: Theme.fsCaption
                font.weight: ag.openRunning ? Theme.wBold : Theme.wRegular
                font.family: Theme.fam(text, Theme.families)
                font.features: { "tnum": 1 }
                text: ag.open ? (ag.openRunning ? I18n.tr("mod-calendar.now") + " · " : "")
                    + C.span(I18n.tr, ag.openEv, ag.loc, ag.dayFmt) : ""
            }
            Text {
                visible: !!det.e.location
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: det.e.location || ""
            }
            // Plain text, as the calendar wrote it: a link in it is text, not a button (no link handling here).
            Text {
                visible: !!det.e.description
                width: parent.width
                wrapMode: Text.WordWrap
                maximumLineCount: 8
                elide: Text.ElideRight
                textFormat: Text.PlainText
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: det.e.description || ""
            }
        }
    }
}
