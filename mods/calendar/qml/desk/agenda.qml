import QtQuick
import qs.core
import qs.components
import ".."
import "../Calendar.js" as C

// The agenda card on the desk (docs/ux/calendar.md "Views"; macOS's "Up Next" widget): today's all-day events as a band,
// the running or next event large with "in 25 min" / "now · until 11:00", then the rest of today and tomorrow's first,
// six rows at most; "Nothing else today" when the day is done. While no calendar is set: the call to action. The desk
// takes no keyboard focus (K43). Ma: the card lives only while the desk is shown; its minute timer runs while visible.
Item {
    // Handed in by ModLoader (K26 loader contract).
    required property var store
    required property var theme
    required property var i18n
    id: dc

    // The desk hides a card of height 0, so the watch is not gated on visibility (as the tasks card does it).
    Watch { doc: "mod.calendar" }

    readonly property var d: Store.docs["mod.calendar"] || ({})
    readonly property bool loaded: Store.docs["mod.calendar"] !== undefined && d.state !== undefined
    readonly property bool none: d.state === "none"
    readonly property string lang: (Store.docs["i18n"] || ({})).locale === "ja" ? "ja" : "en"
    readonly property var loc: Qt.locale(lang)
    readonly property string todayKey: d.today || C.key(new Date())
    readonly property string tomorrowKey: C.nextKey(todayKey)

    property real nowS: Date.now() / 1000
    Timer {
        interval: 30000
        repeat: true
        running: dc.visible && dc.loaded
        onTriggered: dc.nowS = Date.now() / 1000
    }
    onVisibleChanged: nowS = Date.now() / 1000

    readonly property var allDay: C.events(d, todayKey).filter(function (e) { return e.all_day || (e.start < C.dayStart(todayKey) && e.end > C.dayStart(tomorrowKey)) })
    // Timed events from now on, today and tomorrow (once each).
    readonly property var coming: C.upcoming(d, nowS, todayKey).filter(function (e) {
        return e.start < C.dayStart(C.nextKey(tomorrowKey))
    })
    readonly property var hero: coming.length > 0 ? coming[0] : null
    readonly property var rest: coming.slice(1, 6)
    readonly property var notes: C.notes(I18n.tr, d, nowS)

    implicitHeight: loaded ? card.height : 0

    DeskCard {
        id: card
        width: dc.width
        visible: dc.loaded
        Column {
            width: parent.width
            spacing: Theme.xs + 2

            // ---- title: the caption and today's date ----
            Item {
                width: parent.width
                height: cap.implicitHeight
                Text {
                    id: cap
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.weight: Theme.wBold
                    font.letterSpacing: 1
                    font.capitalization: Font.AllUppercase
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr("mod-calendar.title")
                }
                Text {
                    anchors.right: parent.right
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: new Date(C.dayStart(dc.todayKey) * 1000).toLocaleDateString(dc.loc, dc.lang === "ja" ? "M月d日（ddd）" : "ddd d MMM")
                }
            }

            // ---- no calendar set ----
            Column {
                visible: dc.none
                width: parent.width
                spacing: Theme.gap
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr("mod-calendar.no_source")
                }
                Button {
                    label: I18n.tr("mod-calendar.add")
                    icon: "add"
                    onClicked: Store.act("settings.open", { key: "mods.calendar.sources" })
                }
            }

            // ---- today's all-day events: a band of chips ----
            Flow {
                visible: !dc.none && dc.allDay.length > 0
                width: parent.width
                spacing: Theme.xs
                Repeater {
                    model: dc.none ? [] : dc.allDay
                    delegate: Rectangle {
                        required property var modelData
                        width: Math.min(chipText.implicitWidth + 2 * Theme.gap, card.width - 2 * Theme.pad)
                        height: chipText.implicitHeight + Theme.xs
                        radius: height / 2
                        color: Qt.alpha(modelData.color || Theme.accent, 0.22)
                        border.width: 1
                        border.color: Qt.alpha(modelData.color || Theme.accent, 0.6)
                        Accessible.role: Accessible.StaticText
                        Accessible.name: C.a11y(I18n.tr, modelData, dc.todayKey)
                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, parent.width - 2 * Theme.gap)
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            color: Theme.fg
                            font.pixelSize: Theme.fsCaption
                            font.family: Theme.fam(text, Theme.families)
                            text: modelData.title || I18n.tr("mod-calendar.untitled")
                        }
                    }
                }
            }

            // ---- loading / nothing else today ----
            Text {
                visible: !dc.none && dc.hero === null
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: dc.d.state === "loading" ? I18n.tr("mod-calendar.loading")
                    : dc.d.state === "error" ? I18n.tr(dc.d.reason || "mod-calendar.error.all")
                    : I18n.tr("mod-calendar.nothing_else")
            }

            // ---- the next event, large ----
            Item {
                visible: !dc.none && dc.hero !== null
                width: parent.width
                height: heroCol.implicitHeight
                Accessible.role: Accessible.StaticText
                Accessible.name: dc.hero ? C.a11y(I18n.tr, dc.hero, C.key(new Date(dc.hero.start * 1000))) + ", "
                    + C.relative(I18n.tr, dc.hero, dc.nowS, dc.todayKey, dc.loc) : ""
                Rectangle {
                    id: heroBar
                    width: 4
                    height: parent.height
                    radius: 2
                    color: dc.hero ? (dc.hero.color || Theme.accent) : "transparent"
                }
                Column {
                    id: heroCol
                    anchors.left: heroBar.right
                    anchors.leftMargin: Theme.gap
                    anchors.right: parent.right
                    spacing: 1
                    Text {
                        width: parent.width
                        color: dc.hero && C.isRunning(dc.hero, dc.nowS) ? Theme.accent : Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.weight: Theme.wBold
                        font.family: Theme.fam(text, Theme.families)
                        text: dc.hero ? C.relative(I18n.tr, dc.hero, dc.nowS, dc.todayKey, dc.loc) : ""
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        color: Theme.fg
                        font.pixelSize: Theme.fsTitle
                        font.weight: Theme.wBold
                        font.family: Theme.fam(text, Theme.families)
                        text: dc.hero ? (dc.hero.title || I18n.tr("mod-calendar.untitled")) : ""
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                        text: dc.hero ? C.hm(dc.hero.start) + (dc.hero.end > dc.hero.start ? "–" + C.hm(dc.hero.end) : "")
                            + (dc.hero.location ? "  ·  " + dc.hero.location : "")
                            + (dc.hero.calendar ? "  ·  " + dc.hero.calendar : "") : ""
                    }
                }
            }

            // ---- the rest of today and tomorrow ----
            Repeater {
                model: dc.none ? [] : dc.rest
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property string dayKey: C.key(new Date(modelData.start * 1000))
                    readonly property bool firstTomorrow: dayKey === dc.tomorrowKey
                        && (index === 0 ? (dc.hero !== null && C.key(new Date(dc.hero.start * 1000)) !== dc.tomorrowKey)
                            : C.key(new Date(dc.rest[index - 1].start * 1000)) !== dc.tomorrowKey)
                    width: parent.width
                    height: (tomorrowCap.visible ? tomorrowCap.implicitHeight + Theme.xs : 0) + line.implicitHeight + 4
                    Accessible.role: Accessible.StaticText
                    Accessible.name: C.a11y(I18n.tr, modelData, dayKey)
                    Text {
                        id: tomorrowCap
                        visible: row.firstTomorrow
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.weight: Theme.wBold
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("mod-calendar.tomorrow")
                    }
                    Rectangle {
                        id: dot
                        y: line.y + (line.implicitHeight - height) / 2
                        width: 6
                        height: 6
                        radius: 3
                        color: row.modelData.color || Theme.accent
                    }
                    Text {
                        id: line
                        y: tomorrowCap.visible ? tomorrowCap.implicitHeight + Theme.xs : 0
                        anchors.left: dot.right
                        anchors.leftMargin: Theme.gap
                        anchors.right: parent.right
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: C.hm(row.modelData.start) + "  " + (row.modelData.title || I18n.tr("mod-calendar.untitled"))
                    }
                }
            }

            // ---- sources that are offline or failing ----
            Repeater {
                model: dc.none ? [] : dc.notes
                delegate: Text {
                    required property var modelData
                    width: card.width - 2 * Theme.pad
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
}
