import QtQuick
import "../../../../frontend/core"
import "../../../../frontend/components"
import "../Weather.js" as W

// Clock aside (K28 slot `clock.expanded.aside`, at most 140 × 120 px; docs/ux/weather.md, "Clock aside"):
// today's glyph and temperature, the high and low, the chance of rain. A click opens the panel. The
// host mounts it only while the mod is on and its document is available, so no gap is left when off.
// Stale values are dimmed and named; with no data the daemon's reason is the text.
Item {
    id: a

    width: 140
    height: 120
    property bool live: visible
    Watch { doc: "mod.weather"; active: a.live }

    readonly property var d: Store.docs["mod.weather"] || ({})
    readonly property bool ok: d.available === true
    readonly property var now: d.now || ({})
    readonly property bool hasNow: ok && d.now !== undefined
    readonly property var today: d.days && d.days.length > 0 ? d.days[0] : null
    readonly property bool dim: d.tier === "stale" || d.tier === "very_stale"
    readonly property string unitTemp: I18n.tr("mod-weather.unit.temp." + (d.units || "metric"))

    Accessible.role: Accessible.Button
    Accessible.name: hasNow
        ? W.fill(I18n.tr("mod-weather.a11y.widget"), {
            place: d.place ? d.place.name : "",
            temp: W.num(now.temp) + unitTemp,
            condition: I18n.tr("mod-weather.condition." + now.code),
            age: ""
        })
        : I18n.tr(d.reason || "mod-weather.loading")

    Rectangle {
        anchors.fill: parent
        radius: Theme.rLg
        color: Theme.container
        border.width: 1
        border.color: Theme.outline
    }

    Column {
        anchors.centerIn: parent
        spacing: 2
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: a.hasNow ? W.glyph(a.now.code, a.now.is_day) : "—"
            color: Theme.fg
            font.pixelSize: 30
            font.family: Theme.fam(text, Theme.families)
            opacity: a.dim ? Theme.staleOpacity : 1
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: a.hasNow
            text: W.num(a.now.temp) + a.unitTemp
            color: Theme.fg
            font.pixelSize: Theme.fsTitle
            font.family: Theme.fam(text, Theme.families)
            opacity: a.dim ? Theme.staleOpacity : 1
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: a.ok && a.today !== null && a.today.max !== undefined
            text: a.today ? W.num(a.today.max) + "° / " + W.num(a.today.min) + "°" : ""
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: a.ok && a.today !== null && W.has(a.today.pop)
            text: a.today ? W.fill(I18n.tr("mod-weather.aside.rain"), { pop: W.num(a.today.pop) }) : ""
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !a.ok
            width: 120
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            text: I18n.tr(d.reason || "mod-weather.loading")
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Store.act("mod.panel.open", { id: "weather", panel: "weather" })
    }
}
