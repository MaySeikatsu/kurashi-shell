import QtQuick
import qs.core
import qs.components
import "../Weather.js" as W

// Clock aside (K28 slot `clock.expanded.aside`, at most 140 × 120 px; docs/ux/weather.md, "Clock aside"): today's
// glyph and temperature, the high and low, the chance of rain, and the age of the value. A click opens the panel.
// The host mounts it only while the mod is on and its document is available, so no gap is left when it is off.
// A stale value is dimmed and says "Stale"; a value too old to show gives only the time it was last known.
// W19 (row 72): while no place is saved the host hands `reason`. The aside then says "No place set" and offers
// "Set place", which opens Settings on the place key, instead of an empty box.
Item {
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n
    // The daemon's reason while this contribution needs setup (an i18n key); "" otherwise.
    property string reason: ""
    readonly property bool needsSetup: reason !== ""
    id: a

    // The host sizes its loader from the implicit size: an explicit width and height alone collapse it to 0.
    implicitWidth: 140
    implicitHeight: 120
    width: implicitWidth
    height: implicitHeight
    property bool live: visible
    Watch { doc: "mod.weather"; active: a.live }

    readonly property var d: Store.docs["mod.weather"] || ({})
    readonly property bool ok: d.available === true
    readonly property var now: d.now || ({})
    readonly property bool hasNow: ok && d.now !== undefined
    readonly property var today: d.days && d.days.length > 0 ? d.days[0] : null
    readonly property bool stale: ok && d.tier === "stale"
    readonly property bool veryStale: ok && d.tier === "very_stale"
    readonly property string unitTemp: I18n.tr("mod-weather.unit.temp." + (d.units || "metric"))
    readonly property string ageText: {
        var g = W.ageParts(d.age_s)
        return g.n > 0 ? W.fill(I18n.tr(g.key), { n: g.n }) : I18n.tr(g.key)
    }

    Accessible.role: Accessible.Button
    Accessible.name: needsSetup
        ? I18n.tr("frontend.clock.aside.no_place")
        : hasNow
            ? W.fill(I18n.tr("mod-weather.a11y.widget"), {
                place: d.place ? d.place.name : "",
                temp: W.num(now.temp) + unitTemp,
                condition: I18n.tr("mod-weather.condition." + now.code),
                age: a.ageText
            })
            : veryStale
                ? W.fill(I18n.tr("mod-weather.very_stale"), { time: W.hm(d.updated_local) })
                : I18n.tr(d.reason || "mod-weather.loading")
    activeFocusOnTab: true
    Keys.onReturnPressed: Store.act("mod.panel.open", { id: "weather", panel: "weather" })
    Keys.onEnterPressed: Store.act("mod.panel.open", { id: "weather", panel: "weather" })
    Keys.onSpacePressed: Store.act("mod.panel.open", { id: "weather", panel: "weather" })

    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        color: Theme.containerHigh
    }

    // The whole aside opens the panel. It sits under the content, so the setup button takes its own clicks.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Store.act("mod.panel.open", { id: "weather", panel: "weather" })
    }

    Column {
        id: col
        anchors.centerIn: parent
        width: parent.width - Theme.gap * 2
        spacing: 2
        visible: !a.needsSetup
        opacity: a.stale ? Theme.staleOpacity : 1

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: a.hasNow ? W.glyph(a.now.code, a.now.is_day) : "—"
            color: Theme.fg
            font.pixelSize: 22
            font.family: Theme.fam(text, Theme.families)
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: a.hasNow
            text: a.hasNow ? W.num(a.now.temp) + a.unitTemp : ""
            color: Theme.fg
            font.pixelSize: Theme.fsTitle
            font.family: Theme.fam(text, Theme.families)
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: a.hasNow && a.today !== null
            text: a.today !== null ? W.fill(I18n.tr("mod-weather.high_low"), { max: W.deg(a.today.max), min: W.deg(a.today.min) }) : ""
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: a.hasNow && a.today !== null && W.has(a.today.pop)
            text: a.today !== null && W.has(a.today.pop) ? W.fill(I18n.tr("mod-weather.aside.rain"), { pop: W.num(a.today.pop) }) : ""
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }
        // The last line may take two lines (a long age, a long time); it never runs past the box's bottom edge (I82).
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            text: a.veryStale
                ? W.fill(I18n.tr("mod-weather.very_stale"), { time: W.hm(d.updated_local) })
                : a.hasNow
                    ? (a.stale
                        ? I18n.tr("mod-weather.tier.stale") + " · " + a.ageText
                        : W.fill(I18n.tr("mod-weather.updated"), { age: a.ageText }))
                    : I18n.tr(d.reason || "mod-weather.loading")
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }
    }

    // Needs setup (row 72): the words and the one step that fixes them. The button opens Settings on the place key.
    Column {
        id: setup
        anchors.centerIn: parent
        width: parent.width - Theme.gap * 2
        spacing: Theme.gap
        visible: a.needsSetup
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            text: I18n.tr("frontend.clock.aside.no_place")
            color: Theme.fg
            font.pixelSize: Theme.fsLabel
            font.family: Theme.fam(text, Theme.families)
        }
        // A Column places its children itself, so the button sits in a full-width item to be centred there.
        Item {
            width: setup.width
            height: place.height
            // The accent fill: the aside's own box is the container colour, which a plain button would not stand out on.
            Button {
                id: place
                anchors.horizontalCenter: parent.horizontalCenter
                primary: true
                label: I18n.tr("mod-weather.set_place")
                onClicked: Store.act("settings.open", { key: "mods.weather.place" })
            }
        }
    }

    FocusRing { anchors.fill: parent; shown: a.activeFocus; corner: Theme.rSm }
}
