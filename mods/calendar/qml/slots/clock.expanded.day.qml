import QtQuick
import qs.core
import qs.components
import "../Calendar.js" as C

// The selected day's agenda in the clock card (K28 slot `clock.expanded.day`; docs/ux/calendar.md "Views"): up to six
// rows `colour bar · time · title · location`, all-day first, "+ N more"; on today the past rows are dimmed, the
// running one says "now" in the accent and a thin line marks the present. Under the rows, one line per source that is
// offline or failing (never silent). While no calendar is set the host hands `reason`: the call to action instead.
// The selected date comes from the host's `date` when it passes one (CONTRACT-CHANGE row 200), else from the clock
// view this sits in (its `sel`). Ma: the document is watched and the minute timer runs only while visible.
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
    // The clock view hosting this slot (it has the selected day as `sel`), found once.
    property var clockView: null
    Component.onCompleted: {
        var p = parent
        while (p) {
            if (p.sel !== undefined && p.isoDate !== undefined) { clockView = p; break }
            p = p.parent
        }
    }
    readonly property string todayKey: d.today || C.key(new Date())
    readonly property string day: date !== "" ? date : (clockView ? C.key(clockView.sel) : todayKey)
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

    implicitHeight: col.implicitHeight
    implicitWidth: 320

    Column {
        id: col
        width: ag.width
        spacing: Theme.xs

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

        // ---- the rows ----
        Repeater {
            model: ag.needsSetup ? [] : ag.shown
            delegate: Column {
                id: row
                required property var modelData
                required property int index
                readonly property bool past: ag.isToday && C.isPast(modelData, ag.nowS)
                readonly property bool running: ag.isToday && C.isRunning(modelData, ag.nowS)
                width: col.width
                spacing: 2
                Rectangle {
                    visible: row.index === ag.nowIndex && row.index > 0
                    width: parent.width
                    height: 1
                    color: Theme.accent
                }
                Item {
                    width: parent.width
                    height: Math.max(title.implicitHeight, time.implicitHeight) + 4
                    opacity: row.past ? Theme.staleOpacity : 1
                    Accessible.role: Accessible.StaticText
                    Accessible.name: C.a11y(I18n.tr, row.modelData, ag.day) + (row.running ? ", " + I18n.tr("mod-calendar.now") : "")
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
}
