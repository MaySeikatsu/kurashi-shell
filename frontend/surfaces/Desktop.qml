import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"
import "../components/island"

// Desktop widgets (K43; SekaiPop's desk): cards on the bottom layer, under the windows, on one side of each output —
// the time as four keys with the date and the day's progress, this month with today marked, what is playing (hidden
// while nothing plays) and today's weather (while the weather mod serves a place). Opt-in per output
// (`desktop.enabled`; the sekai decor recommends it). A pure view: every value comes from a document, every press is
// an action.
// Ma: no surface while off; the documents are watched only while the surface is shown; nothing animates on its own —
// the clock changes when svc.clock's minute patch arrives. Content-sized (K16): the window is the column of cards.
// Mods add cards (K46, row 120: `desk:<name>` → the mod's `qml/desk/<name>.qml`), each loaded only while the desk is
// shown, at the column's width; a card sets its own implicitHeight (0 when it has nothing to say). A mod's cards follow
// the manifest's `provides` order: the `qml` map is sorted by key, so it cannot give one (W36).
// Order and sides (K48 (4), K71, W44 point 15): two columns at once — `desktop.left` and `desktop.right`, each top to
// bottom (core ids and `mod:<id>:<name>`); a card neither list names stands on `desktop.side`, after that side's listed
// cards (core ones first); a card both lists name stands on the other side (see `arrange`). One window per output: content-sized on
// its side while one column has cards, the output's width (input only over the columns) while both do. Hidden (K65,
// W36): a card is left out while its switch is off (core: `desktop.<card>`, the switch Settings shows) or its id is in
// `desktop.hidden` (a mod card has no switch of its own).
// Edit mode (SekaiPop "Edit Desktop", macOS "Edit Widgets"; docs/ux/desktop.md v3–v4): the "Edit" key on hover lifts the
// columns over the windows with the keyboard, every card shows (a placeholder says when it shows; a hidden one says
// "Hidden"), drag or Alt+Up/Down reorders, the side key (or Alt+Left/Right) moves a card to the other column, the eye
// (or Space) shows or hides any card, and Done writes both lists, the switches and the hidden list as one `apply` (one
// undo step); Escape puts everything back. Nothing is written while editing.
PanelWindow {
    id: desk
    required property var modelData
    screen: modelData

    BarConfig { id: bars; screen: desk.screen }
    readonly property bool on: bars.valueOf("desktop.enabled", false) === true
    readonly property string mainSide: bars.valueOf("desktop.side", "right") === "left" ? "left" : "right"
    function want(key) { return bars.valueOf("desktop." + key, true) === true }

    // Edit mode. While on, the columns sit on the top layer and hold the keyboard (exclusive: a bottom-layer surface
    // gets keys only after a second click in sway and niri, and Escape must always work); Done or Escape gives both back.
    property bool editing: false
    // What the edit shows before Done: the core cards' switches (`desktop.<id>`) as staged.
    property var staged: ({})
    property string editError: ""

    // K71: the cards keep clear of every edge's zone (a bar, the frame, a pinned sidebar), from runtime.layout.
    Watch { doc: "runtime.layout" }
    readonly property var lay: ShellLayout.of(screen ? screen.name : "")
    function zoneOf(e) { var x = (lay.edges || {})[e] || {}; return x.holder && x.holder !== "none" && typeof x.reserve === "number" ? x.reserve : 0 }

    // Which columns stand: a side with cards (in edit mode both, so a card can cross).
    readonly property bool leftOn: editing || leftModel.count > 0
    readonly property bool rightOn: editing || rightModel.count > 0
    readonly property bool both: leftOn && rightOn

    visible: on
    WlrLayershell.layer: editing ? WlrLayer.Top : WlrLayer.Bottom
    WlrLayershell.namespace: "kurashi-desktop"
    WlrLayershell.keyboardFocus: editing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    anchors { top: true; left: desk.leftOn || !desk.rightOn; right: desk.rightOn }
    // The Edit key sits above the first card's padding, its bottom 2 px above the keycaps' top (they start at the padding),
    // so it covers no content of the clock's keys (W36). The window starts `keyLift` above the cards; the cards keep 28 px
    // under the top edge's zone, or the key's clearance from it when that is more.
    readonly property int keyLift: Math.max(0, editKey.height - Theme.pad + 2)
    readonly property int colTop: Math.max(28, keyLift + 8)
    readonly property int sideGap: 32
    margins {
        top: zoneOf("top") + colTop - keyLift
        left: desk.both ? 0 : zoneOf("left") + sideGap
        right: desk.both ? 0 : zoneOf("right") + sideGap
    }
    implicitWidth: desk.cardW
    implicitHeight: Math.max(1, Math.max(leftCol.height, rightCol.height) + keyLift)
    // While both columns stand only they take the pointer (the desk between them is the windows' and the wallpaper's).
    mask: Region {
        item: leftCol
        Region { item: rightCol }
        Region { item: editKey }
    }
    onOnChanged: if (!on) cancelEdit()

    Watch { doc: "svc.clock"; active: desk.visible }
    Watch { doc: "svc.media"; active: desk.visible && (desk.showsNow("media") || desk.editing) }
    Watch { doc: "mod.weather"; active: desk.visible && (desk.showsNow("weather") || desk.editing) && desk.weatherMod }
    Watch { doc: "mods"; active: desk.visible }
    readonly property var clock: Store.docs["svc.clock"] || ({})
    readonly property var media: Store.docs["svc.media"] || ({})
    readonly property var weather: Store.docs["mod.weather"] || ({})
    readonly property string locale: (Store.docs["i18n"] || {}).locale || "en"
    // On: an enabled native mod carries its `qml` map (PROTOCOL §5).
    readonly property bool weatherMod: {
        var m = (Store.docs["mods"] || {}).mods || []
        for (var i = 0; i < m.length; i++) if (m[i].id === "weather" && m[i].qml !== undefined) return true
        return false
    }
    function modName(id) {
        var m = (Store.docs["mods"] || {}).mods || []
        for (var i = 0; i < m.length; i++) if (m[i].id === id) return I18n.tr(m[i].name || id)
        return id
    }
    // The desk cards of enabled mods as [{mod, provide, url}] in the manifest's `provides` order (the `qml` map is sorted
    // by key, so it cannot give that order; the mods document lists `provides` as the manifest does). A card with no file
    // is not listed.
    function deskCardsOf(doc) {
        var out = []
        var list = (doc && doc.mods) || []
        for (var i = 0; i < list.length; i++) {
            var m = list[i], q = m.qml || ({}), p = m.provides || []
            for (var j = 0; j < p.length; j++)
                if (String(p[j]).indexOf("desk:") === 0 && typeof q[p[j]] === "string" && q[p[j]] !== "")
                    out.push({ mod: m.id, provide: p[j], url: q[p[j]] })
        }
        return out
    }

    // The desk cards of enabled mods as [{id: "mod:<mod>:<name>", url, mod}]. The list is rebuilt only when the URLs
    // change: the `mods` document also changes when a mod starts or stops running (a card's own subscription does that),
    // and a new list would remake every card, which would unsubscribe and resubscribe it, without end.
    readonly property var modsDoc: Store.docs["mods"]
    readonly property string deskKey: desk.visible
        ? JSON.stringify(desk.deskCardsOf(desk.modsDoc).map(function (c) {
            return { id: "mod:" + c.mod + ":" + c.provide.substring(5), url: c.url, mod: c.mod }
        })) : "[]"
    property var modCards: []
    onDeskKeyChanged: modCards = JSON.parse(deskKey)

    // ---- order -------------------------------------------------------------------------------------------------------
    readonly property var coreIds: ["clock", "calendar", "media", "weather"]
    function listOf(side) {
        var o = bars.valueOf("desktop." + side, null)
        return Array.isArray(o) ? o.filter(function (s) { return typeof s === "string" }) : (side === "right" ? coreIds : [])
    }
    readonly property var configLeft: listOf("left")
    readonly property var configRight: listOf("right")
    // Every card the desk can show now, in their unlisted order: core first, then mods' in mod order.
    readonly property var available: coreIds.concat(modCards.map(function (c) { return c.id }))
    function urlOf(id) {
        for (var i = 0; i < modCards.length; i++) if (modCards[i].id === id) return modCards[i].url
        return ""
    }
    // Both columns from the two lists: each narrowed to the available cards, and every available card neither names after
    // the main side's listed ones. A card both name stands on the other side: the main side's list names every core card
    // by default, so naming one on the other side is the move (desktop.left = ["calendar"] takes the calendar left).
    function arrange(left, right) {
        var out = { left: [], right: [] }, seen = {}
        var first = mainSide === "left" ? [["right", right], ["left", left]] : [["left", left], ["right", right]]
        for (var s = 0; s < 2; s++) {
            var side = first[s][0], l = first[s][1]
            for (var i = 0; i < l.length; i++)
                if (available.indexOf(l[i]) >= 0 && !seen[l[i]]) { seen[l[i]] = true; out[side].push(l[i]) }
        }
        for (var j = 0; j < available.length; j++) if (!seen[available[j]]) out[mainSide].push(available[j])
        return out
    }
    function modelOf(side) { return side === "left" ? leftModel : rightModel }
    function modelIds(side) {
        var m = modelOf(side), out = []
        for (var i = 0; i < m.count; i++) out.push(m.get(i).cid)
        return out
    }
    // The models follow the order in place (moves, not a rebuild), so a card keeps its object, its subscriptions and its
    // keyboard focus. While editing they follow the edit; else the config.
    function syncSide(m, ids) {
        for (var i = 0; i < ids.length; i++) {
            var at = -1
            for (var j = i; j < m.count; j++) if (m.get(j).cid === ids[i]) { at = j; break }
            if (at < 0) m.insert(i, { cid: ids[i], url: urlOf(ids[i]) })
            else if (at !== i) m.move(at, i, 1)
        }
        if (m.count > ids.length) m.remove(ids.length, m.count - ids.length)
    }
    function sync() {
        var a = editing ? arrange(modelIds("left"), modelIds("right")) : arrange(configLeft, configRight)
        // (The two lists are disjoint: a card that crossed sides is inserted on one and removed from the other.)
        syncSide(leftModel, a.left)
        syncSide(rightModel, a.right)
    }
    ListModel { id: leftModel }
    ListModel { id: rightModel }
    readonly property string syncKey: JSON.stringify([configLeft, configRight, available, mainSide])
    onSyncKeyChanged: Qt.callLater(sync)
    Component.onCompleted: sync()

    // ---- edit mode ---------------------------------------------------------------------------------------------------
    function locked(key) {
        var p = bars.entry(key)
        return !!p && (!!p.forced_by || (p.source || {}).kind === "forced" || (p.source || {}).kind === "nix")
    }
    // A layer above the user's (Nix, a forced value) holds an order: edit mode says so and moves nothing (Shōjiki).
    readonly property bool orderLocked: locked("desktop.left") || locked("desktop.right")
    // Hidden (K65): a listed id is left out whatever its switch says. A mod card has no switch, so the list is its only
    // hide; a core card keeps its switch (the one Settings shows), and the list may name it as well.
    readonly property var hiddenList: { var h = bars.valueOf("desktop.hidden", []); return Array.isArray(h) ? h : [] }
    function hiddenIn(id) {
        if (hiddenList.indexOf(id) >= 0) return true
        return id.indexOf("mod:") !== 0 && !want(id)
    }
    // What the desk shows now, not the staged edit: the watches and the loaders follow it (a hidden card is not made).
    function showsNow(id) { return !hiddenIn(id) }
    // The eye is locked when a layer above the user sets what it writes: the card's switch, or the list for a mod card.
    function switchLocked(id) { return locked(id.indexOf("mod:") === 0 ? "desktop.hidden" : "desktop." + id) }
    readonly property bool anySwitchLocked: {
        for (var i = 0; i < available.length; i++) if (switchLocked(available[i])) return true
        return false
    }
    function shown(id) {
        return editing && staged[id] !== undefined ? staged[id] : !hiddenIn(id)
    }
    function slotOf(side, i) { var r = side === "left" ? leftCol.rep : rightCol.rep; return r ? r.itemAt(i) : null }
    function startEdit() {
        if (editing) return
        staged = ({})
        editError = ""
        editing = true
        sync()
        Qt.callLater(function () {
            var s = slotOf(mainSide, 0) || slotOf(mainSide === "left" ? "right" : "left", 0)
            if (s) s.forceActiveFocus()
        })
    }
    function cancelEdit() {
        if (!editing) return
        // The focus leaves the card first: a card with the focus cannot drop out of the Tab order (Qt warns).
        root.forceActiveFocus()
        editing = false
        staged = ({})
        editError = ""
        sync()
    }
    function toggleShown(id) {
        if (switchLocked(id)) return
        var s = Object.assign({}, staged)
        s[id] = !shown(id)
        staged = s
    }
    function moveCard(side, from, to) {
        var m = modelOf(side)
        if (orderLocked || to < 0 || to >= m.count || from === to) return
        m.move(from, to, 1)
    }
    // The card at `index` of `side` to the end of the other column; the focus goes with it.
    function moveSide(side, index) {
        if (orderLocked) return
        var m = modelOf(side), other = side === "left" ? "right" : "left", o = modelOf(other)
        if (index < 0 || index >= m.count) return
        var it = m.get(index), cid = it.cid, url = it.url
        root.forceActiveFocus()
        m.remove(index, 1)
        o.append({ cid: cid, url: url })
        var at = o.count - 1
        Qt.callLater(function () { var s = desk.slotOf(other, at); if (s) s.forceActiveFocus() })
    }
    // Done: both orders and the switches that changed, as one apply (one undo step); nothing when nothing changed.
    function saveEdit() {
        if (!editing) return
        var ops = []
        var now = { left: modelIds("left"), right: modelIds("right") }
        var was = arrange(configLeft, configRight)
        if (!orderLocked && JSON.stringify(now) !== JSON.stringify(was)) {
            if (JSON.stringify(now.left) !== JSON.stringify(configLeft)) ops.push({ set: "desktop.left", value: now.left })
            if (JSON.stringify(now.right) !== JSON.stringify(configRight)) ops.push({ set: "desktop.right", value: now.right })
        }
        // A core card's switch is its own key; a mod card's hide is its entry in the list. The list goes out once, in the
        // same apply, so one undo puts it back with the rest.
        var hidden = hiddenList.slice()
        var listed = false
        for (var id in staged) {
            var s = staged[id]
            var mod = id.indexOf("mod:") === 0
            if (!mod && s !== want(id)) ops.push({ set: "desktop." + id, value: s })
            var at = hidden.indexOf(id)
            if (s && at >= 0) { hidden.splice(at, 1); listed = true }
            else if (!s && at < 0 && mod) { hidden.push(id); listed = true }
        }
        if (listed) ops.push({ set: "desktop.hidden", value: hidden })
        if (ops.length === 0) { cancelEdit(); return }
        editError = ""
        if (Quickshell.env("KURASHI_DESK_LOG") === "1") console.log("desk-save " + JSON.stringify(ops))
        Store.apply(ops, function (errors) {
            if (!errors) { root.forceActiveFocus(); editing = false; staged = ({}); return }
            var c = errors.length ? (errors[0].code || "") : ""
            editError = c === "disconnected" ? I18n.tr("frontend.desktop.edit.disconnected")
                : I18n.tr("frontend.desktop.edit.refused") + (c !== "" ? " (" + I18n.tr(c) + ")" : "")
        })
    }
    // A one-time wiggle when edit mode starts (SekaiPop's shelf, iOS): three swings, then still. Off with reduced motion.
    signal wiggle()
    onEditingChanged: if (editing && Theme.springOn) wiggle()

    readonly property int cardW: 300
    // A card: a Block with the panel's padding; keycap chrome outlines it and drops its hard shadow. `hasContent` false =
    // nothing to show now (the column skips it; edit mode shows a placeholder instead).
    component Card: Block {
        default property alias body: inner.data
        property bool hasContent: true
        width: desk.cardW
        height: inner.childrenRect.height + 2 * Theme.pad + 2 * inset + Theme.shadowDy
        radius: Theme.rLg + 4
        fill: Theme.surfaceAlpha
        flatBorder: Theme.outline
        // Inside the Block's fill (its default property), which already sits within the outline and ring.
        Item {
            id: inner
            x: Theme.pad
            y: Theme.pad
            width: parent.width - 2 * Theme.pad
            height: childrenRect.height
        }
    }
    component Caption: Text {
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.weight: Theme.wBold
        font.letterSpacing: 1
        font.capitalization: Font.AllUppercase
        font.family: Theme.fam(text, Theme.families)
    }

    // ---- clock: four keys, the date, the day's progress ----
    component ClockCard: Card {
        Column {
            width: parent.width
            spacing: Theme.gap
            KeyClock {
                anchors.horizontalCenter: parent.horizontalCenter
                hh: desk.clock.hh ?? "--"
                mm: desk.clock.mm ?? "--"
                animate: desk.visible
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                text: {
                    var d = desk.clock.date ? new Date(desk.clock.date + "T12:00:00") : null
                    return d ? d.toLocaleDateString(Qt.locale(desk.locale), "dddd, d MMMM") : ""
                }
            }
            // The day's progress (SekaiPop's clock card): how much of today has gone, from the minute patch.
            Rectangle {
                width: parent.width
                height: Theme.keycap ? 12 : 6
                radius: height / 2
                color: Theme.keycap ? Theme.ring : Theme.containerHigh
                border.width: Theme.outlineW > 0 ? Theme.outlineW : 0
                border.color: Theme.line
                readonly property real day: ((parseInt(desk.clock.hh) || 0) * 60 + (parseInt(desk.clock.mm) || 0)) / 1440
                Rectangle {
                    x: parent.border.width; y: parent.border.width
                    height: parent.height - 2 * y
                    width: Math.max(height, (parent.width - 2 * x) * parent.day)
                    radius: height / 2
                    color: Theme.accent
                }
            }
        }
    }

    // ---- this month ----
    component CalendarCard: Card {
        Column {
            id: cal
            width: parent.width
            spacing: Theme.xs + 2
            readonly property date today: desk.clock.date ? new Date(desk.clock.date + "T12:00:00") : new Date()
            // The first column follows clock.week_start (auto: Sunday for Japanese, Monday otherwise), as the
            // island's calendar does.
            readonly property int first: {
                var w = bars.valueOf("clock.week_start", "auto")
                if (w === "sunday") return 0
                if (w === "saturday") return 6
                if (w === "monday") return 1
                return desk.locale.indexOf("ja") === 0 ? 0 : 1
            }
            readonly property int lead: (new Date(today.getFullYear(), today.getMonth(), 1).getDay() - first + 7) % 7
            readonly property int days: new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate()
            Caption {
                width: parent.width
                text: cal.today.toLocaleDateString(Qt.locale(desk.locale), "MMMM yyyy")
            }
            Grid {
                columns: 7
                spacing: 4
                readonly property real cell: (cal.width - 6 * spacing) / 7
                Repeater {
                    model: 7
                    delegate: Text {
                        required property int index
                        width: parent.cell
                        horizontalAlignment: Text.AlignHCenter
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.weight: Theme.wBold
                        font.family: Theme.fam(text, Theme.families)
                        text: Qt.locale(desk.locale).dayName((cal.first + index) % 7, Locale.NarrowFormat)
                    }
                }
                Repeater {
                    model: cal.lead + cal.days
                    delegate: Item {
                        required property int index
                        readonly property int day: index - cal.lead + 1
                        readonly property bool isToday: day === cal.today.getDate()
                        width: parent.cell
                        height: 26 + (Theme.keycap ? 2 : 0)
                        Rectangle {
                            visible: parent.day > 0 && parent.isToday
                            anchors.centerIn: parent
                            width: 28; height: 24
                            radius: 12
                            color: Theme.accent
                            border.width: Theme.outlineW > 0 ? Theme.outlineW : 0
                            border.color: Theme.line
                        }
                        Text {
                            visible: parent.day > 0
                            anchors.centerIn: parent
                            color: parent.isToday ? Theme.fgOnAccent : Theme.fg
                            font.pixelSize: Theme.fs
                            font.weight: parent.isToday ? Theme.wBold : Theme.wMedium
                            font.family: Theme.fam(text, Theme.families)
                            text: parent.day
                        }
                    }
                }
            }
        }
    }

    // ---- now playing: shown while a player plays or is paused on a track ----
    // W24 (K48): on the cover's colours when the daemon has them (`art_colors`: data colours, checked for contrast),
    // with the live level bars (LevelBars watches `svc.audio.spectrum` only while they show and the track plays).
    // Kept as its own component: the media card's look is W24-media's.
    component MediaCard: Card {
        id: mediaCard
        hasContent: desk.media.available === true && (desk.media.title || "") !== ""
        readonly property var cover: desk.media.art_colors && typeof desk.media.art_colors.bg === "string" ? desk.media.art_colors : null
        readonly property color ink: cover ? cover.fg : Theme.fg
        fill: cover ? cover.bg : Theme.surfaceAlpha
        Row {
            width: parent.width
            spacing: Theme.pad
            Rectangle {
                id: art
                width: 72; height: 72
                radius: Theme.rLg
                color: Theme.selected
                border.width: Theme.outlineW > 0 ? Theme.outlineW : 0
                border.color: Theme.line
                clip: true
                Image {
                    id: coverImg
                    anchors.fill: parent
                    anchors.margins: parent.border.width
                    source: desk.visible ? (desk.media.art_url || "") : ""
                    sourceSize: Qt.size(144, 144)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
                Icon {
                    anchors.centerIn: parent
                    visible: !coverImg.visible
                    name: "music_note"
                    glyph: "♪"
                    filled: true
                    size: 32
                    color: Theme.fgOnSelected
                }
            }
            Column {
                width: parent.width - art.width - parent.spacing
                spacing: 2
                Row {
                    width: parent.width
                    spacing: Theme.gap
                    Caption {
                        color: mediaCard.cover ? mediaCard.ink : Theme.dim
                        text: I18n.tr("frontend.desktop.now_playing")
                    }
                    LevelBars {
                        anchors.verticalCenter: parent.verticalCenter
                        running: desk.visible && mediaCard.visible && desk.media.playing === true
                        color: mediaCard.cover ? mediaCard.cover.accent : Theme.accent
                        bars: 6
                        maxH: Theme.fsCaption
                    }
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    color: mediaCard.ink
                    font.pixelSize: Theme.fs + 1
                    font.weight: Theme.wBold
                    font.family: Theme.fam(text, Theme.families)
                    text: desk.media.title || ""
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    color: mediaCard.cover ? mediaCard.ink : Theme.dim
                    font.pixelSize: Theme.fs - 1
                    font.family: Theme.fam(text, Theme.families)
                    text: desk.media.artist || ""
                }
                Row {
                    spacing: Theme.xs
                    readonly property var can: desk.media.can || ({})
                    IconButton {
                        icon: "skip_previous"; glyph: "⏮"
                        a11y: I18n.tr("action.media.prev")
                        enabled: parent.can.prev === true
                        onClicked: Store.act("media.prev")
                    }
                    IconButton {
                        icon: desk.media.playing ? "pause" : "play_arrow"; glyph: desk.media.playing ? "⏸" : "▶"
                        a11y: I18n.tr("action.media.play_pause")
                        lit: true
                        enabled: parent.can.play === true || parent.can.pause === true
                        onClicked: Store.act("media.play_pause")
                    }
                    IconButton {
                        icon: "skip_next"; glyph: "⏭"
                        a11y: I18n.tr("action.media.next")
                        enabled: parent.can.next === true
                        onClicked: Store.act("media.next")
                    }
                }
            }
        }
    }

    // ---- weather: while the weather mod is on and serves today's values ----
    component WeatherCard: Card {
        id: wcard
        readonly property var now: desk.weather.now || ({})
        hasContent: desk.weatherMod && desk.weather.available === true && desk.weather.now !== undefined
        Row {
            width: parent.width
            spacing: Theme.pad
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: desk.conditionIcon(wcard.now.code, wcard.now.is_day)
                glyph: "☁"
                filled: true
                size: 52
                color: Theme.secondary
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Caption { text: desk.weather.place ? desk.weather.place.name : "" }
                Text {
                    color: Theme.fg
                    font.pixelSize: 34
                    font.weight: Font.Black
                    font.family: Theme.fam(text, Theme.families)
                    text: wcard.now.temp !== undefined ? Math.round(wcard.now.temp) + "°" : "—"
                }
                Text {
                    color: Theme.dim
                    font.pixelSize: Theme.fs - 1
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr("mod-weather.condition." + (wcard.now.code || "unknown"))
                }
            }
        }
    }

    // ---- a mod's card (K46): its file, at the column's width; height 0 = nothing to say ----
    component ModCard: ModLoader {
        property string cardUrl: ""
        readonly property bool hasContent: item ? item.implicitHeight > 0 : false
        width: desk.cardW
        url: cardUrl
        shown: desk.visible
        height: item ? item.implicitHeight : 0
    }

    // Edit mode's stand-in for a card with nothing to show now: its name and when it shows.
    component Placeholder: Card {
        id: ph
        property string title: ""
        property string note: ""
        Column {
            width: parent.width
            spacing: 2
            Caption { width: parent.width; text: ph.title }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fs - 1
                font.family: Theme.fam(text, Theme.families)
                text: ph.note
            }
        }
    }

    // A mod card's name: its catalog key `mod-<id>.desk.<name>` when the mod has one, else the mod's name with the card's.
    function cardTitle(id) {
        if (id.indexOf("mod:") !== 0) return I18n.tr("frontend.desktop.card." + id)
        var parts = id.split(":")
        var key = "mod-" + parts[1] + ".desk." + parts[2]
        var t = I18n.tr(key)
        if (t !== key) return t
        return parts[2] === parts[1] ? modName(parts[1]) : modName(parts[1]) + " · " + parts[2]
    }
    function placeholderNote(id) {
        if (id === "media") return I18n.tr("frontend.desktop.edit.note_media")
        if (id === "weather") return I18n.tr(weatherMod ? "frontend.desktop.edit.note_weather_place" : "frontend.desktop.edit.note_weather_mod")
        return I18n.tr("frontend.desktop.edit.note_mod")
    }

    Item {
        id: root
        width: desk.both ? desk.width : desk.cardW
        height: Math.max(leftCol.height, rightCol.height) + desk.keyLift
        focus: true
        Keys.onEscapePressed: event => { desk.cancelEdit(); event.accepted = true }
        HoverHandler { id: deskHover }

        Loader {
            id: leftCol
            readonly property string side: "left"
            readonly property var rep: item ? item.rep : null
            // Sized by its column (a Loader with a size of its own would size the column instead).
            active: desk.leftOn
            x: desk.both ? desk.zoneOf("left") + desk.sideGap : 0
            y: desk.keyLift
            sourceComponent: columnC
        }
        Loader {
            id: rightCol
            readonly property string side: "right"
            readonly property var rep: item ? item.rep : null
            active: desk.rightOn
            x: desk.both ? root.width - desk.zoneOf("right") - desk.sideGap - desk.cardW : 0
            y: desk.keyLift
            sourceComponent: columnC
        }

        // The way in: a key above the main column's first card while the pointer is over the desk (or Tab reaches it).
        // Above the card's padding, it covers no card content (W36: it used to sit over the clock's last digit).
        Button {
            id: editKey
            objectName: "desk-edit"
            readonly property Item main: desk.mainSide === "left" && desk.leftOn || !desk.rightOn ? leftCol : rightCol
            visible: !desk.editing && (deskHover.hovered || editKey.activeFocus)
            y: 0
            x: main.x + desk.cardW - width - Theme.gap
            icon: "edit"
            label: I18n.tr("frontend.desktop.edit.start")
            onClicked: desk.startEdit()
        }
    }

    // One column of cards (its side from the Loader that holds it).
    Component {
        id: columnC
        Column {
            id: cards
            readonly property string side: parent ? parent.side : "right"
            readonly property var model: desk.modelOf(side)
            property alias rep: rep
            readonly property string other: side === "left" ? "right" : "left"
            width: desk.cardW
            spacing: Theme.pad + 4
            move: Transition {
                enabled: Theme.springOn
                NumberAnimation { properties: "y"; duration: Theme.stdMs; easing.type: Easing.OutCubic }
            }

            // ---- edit mode's bar (on the main column): what this is, Cancel and Done, and why a save was refused ----
            Card {
                visible: desk.editing && cards.side === desk.mainSide
                fill: Theme.panel
                Column {
                    width: parent.width
                    spacing: Theme.gap
                    Row {
                        width: parent.width
                        spacing: Theme.gap
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - cancelKey.width - doneKey.width - 2 * parent.spacing
                            elide: Text.ElideRight
                            color: Theme.fg
                            font.pixelSize: Theme.fs + 1
                            font.weight: Theme.wBold
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.tr("frontend.desktop.edit.title")
                        }
                        Button {
                            id: cancelKey
                            objectName: "desk-cancel"
                            label: I18n.tr("frontend.desktop.edit.cancel")
                            onClicked: desk.cancelEdit()
                        }
                        Button {
                            id: doneKey
                            objectName: "desk-done"
                            primary: true
                            label: I18n.tr("frontend.desktop.edit.done")
                            onClicked: desk.saveEdit()
                        }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.dim
                        font.pixelSize: Theme.fs - 2
                        font.family: Theme.fam(text, Theme.families)
                        text: desk.orderLocked ? I18n.tr("frontend.desktop.edit.order_locked")
                                               : I18n.tr("frontend.desktop.edit.hint")
                    }
                    Text {
                        visible: desk.anySwitchLocked
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.dim
                        font.pixelSize: Theme.fs - 2
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("frontend.desktop.edit.switch_locked")
                    }
                    Text {
                        visible: desk.editError !== ""
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.error
                        font.pixelSize: Theme.fs - 2
                        font.family: Theme.fam(text, Theme.families)
                        text: "✕ " + desk.editError
                    }
                }
            }
            // An empty column in edit mode: where a card lands when it is moved here.
            Rectangle {
                visible: desk.editing && rep.count === 0
                width: desk.cardW
                height: emptyText.implicitHeight + 2 * Theme.pad
                radius: Theme.rLg + 4
                color: "transparent"
                border.width: 2
                border.color: Qt.alpha(Theme.accent, 0.7)
                Text {
                    id: emptyText
                    anchors.centerIn: parent
                    width: parent.width - 2 * Theme.pad
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: Theme.fg
                    font.pixelSize: Theme.fs - 1
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr("frontend.desktop.edit.empty_side")
                }
            }

            Repeater {
                id: rep
                model: cards.model
                delegate: Item {
                    id: slot
                    required property int index
                    required property string cid
                    required property string url
                    readonly property bool isMod: cid.indexOf("mod:") === 0
                    readonly property bool wanted: desk.shown(cid)
                    readonly property bool hasContent: real.item ? real.item.hasContent === true : false
                    readonly property bool showReal: hasContent && (wanted || desk.editing)
                    readonly property bool locked: desk.switchLocked(cid)
                    // Pointer drag (edit mode): the card follows the pointer; crossing a neighbour's middle moves it there.
                    property bool dragging: false
                    property real grabY: 0
                    property real pointerTop: 0
                    readonly property real dragDy: dragging ? pointerTop - y : 0

                    width: desk.cardW
                    height: desk.editing ? (showReal ? real.height : stand.height) : (showReal ? real.height : 0)
                    visible: desk.editing || showReal
                    z: dragging ? 10 : 0
                    transform: [
                        Translate { y: slot.dragDy },
                        Rotation {
                            id: tilt
                            origin.x: slot.width / 2
                            origin.y: slot.height / 2
                            angle: 0
                        }
                    ]
                    SequentialAnimation {
                        id: wiggleAnim
                        NumberAnimation { target: tilt; property: "angle"; to: 1.6; duration: 60 }
                        NumberAnimation { target: tilt; property: "angle"; to: -1.6; duration: 110 }
                        NumberAnimation { target: tilt; property: "angle"; to: 1.0; duration: 100 }
                        NumberAnimation { target: tilt; property: "angle"; to: 0; duration: 90 }
                    }
                    Connections {
                        target: desk
                        function onWiggle() { wiggleAnim.start() }
                    }

                    activeFocusOnTab: desk.editing
                    objectName: "deskcard:" + cid
                    Accessible.role: Accessible.ListItem
                    Accessible.name: desk.cardTitle(cid) + (wanted ? "" : " · " + I18n.tr("frontend.desktop.edit.hidden"))
                    Accessible.description: I18n.tr(cards.side === "left" ? "frontend.desktop.edit.on_left" : "frontend.desktop.edit.on_right")
                    Keys.onPressed: event => {
                        if (!desk.editing) return
                        var alt = (event.modifiers & Qt.AltModifier) !== 0
                        var next = null
                        // Alt+Left/Right: to the other column when that is the way (left column → right, and back).
                        var toOther = alt && ((event.key === Qt.Key_Right && cards.side === "left")
                                              || (event.key === Qt.Key_Left && cards.side === "right"))
                        if (event.key === Qt.Key_Up && alt) desk.moveCard(cards.side, slot.index, slot.index - 1)
                        else if (event.key === Qt.Key_Down && alt) desk.moveCard(cards.side, slot.index, slot.index + 1)
                        else if (toOther) desk.moveSide(cards.side, slot.index)
                        else if (event.key === Qt.Key_Up) next = rep.itemAt(slot.index - 1)
                        else if (event.key === Qt.Key_Down) next = rep.itemAt(slot.index + 1)
                        else if (!alt && ((event.key === Qt.Key_Right && cards.side === "left")
                                          || (event.key === Qt.Key_Left && cards.side === "right"))) {
                            var o = desk.modelOf(cards.other)
                            next = o.count > 0 ? desk.slotOf(cards.other, Math.min(slot.index, o.count - 1)) : null
                        }
                        else if (event.key === Qt.Key_Space) desk.toggleShown(slot.cid)
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) desk.saveEdit()
                        else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) { event.accepted = true; return }
                        else return
                        if (next) next.forceActiveFocus()
                        event.accepted = true
                    }

                    // The card itself: made while it is shown (a mod's card keeps its subscriptions for as long as it shows, and
                    // says itself when it has nothing to show) and while editing. A hidden card is not made outside edit mode
                    // (Ma). In edit mode the card's own controls are out of the Tab order: the card keys are the tab stops.
                    Loader {
                        id: real
                        active: slot.wanted || desk.editing
                        visible: slot.showReal
                        enabled: !desk.editing
                        opacity: slot.wanted ? 1 : 0.45
                        sourceComponent: slot.isMod ? cMod
                            : slot.cid === "clock" ? cClock
                            : slot.cid === "calendar" ? cCalendar
                            : slot.cid === "media" ? cMedia
                            : slot.cid === "weather" ? cWeather : null
                        onLoaded: if (slot.isMod) item.cardUrl = Qt.binding(function () { return slot.url })
                    }
                    Loader {
                        id: stand
                        active: desk.editing && !slot.showReal
                        visible: active
                        opacity: slot.wanted ? 1 : 0.45
                        sourceComponent: Placeholder {
                            title: desk.cardTitle(slot.cid)
                            note: desk.placeholderNote(slot.cid)
                        }
                    }

                    // ---- edit mode: the outline, the drag surface (it also keeps clicks off the card's own keys) and
                    // the card's keys: up, down, the other side, show/hide ----
                    Rectangle {
                        visible: desk.editing
                        anchors.fill: parent
                        anchors.bottomMargin: Theme.shadowDy
                        radius: Theme.rLg + 4
                        color: "transparent"
                        border.width: slot.activeFocus || slot.dragging ? 3 : 2
                        border.color: slot.activeFocus || slot.dragging ? Theme.focusRing : Qt.alpha(Theme.accent, 0.7)
                    }
                    MouseArea {
                        visible: desk.editing
                        anchors.fill: parent
                        preventStealing: true
                        cursorShape: slot.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        onPressed: mouse => {
                            slot.forceActiveFocus()
                            if (desk.orderLocked) return
                            slot.grabY = mouse.y
                            slot.pointerTop = slot.y
                            slot.dragging = true
                        }
                        onPositionChanged: mouse => {
                            if (!slot.dragging) return
                            slot.pointerTop = mapToItem(cards, mouse.x, mouse.y).y - slot.grabY
                            var prev = rep.itemAt(slot.index - 1)
                            var nxt = rep.itemAt(slot.index + 1)
                            if (prev && slot.pointerTop < prev.y + prev.height / 2) desk.moveCard(cards.side, slot.index, slot.index - 1)
                            else if (nxt && slot.pointerTop + slot.height > nxt.y + nxt.height / 2) desk.moveCard(cards.side, slot.index, slot.index + 1)
                        }
                        onReleased: slot.dragging = false
                        onCanceled: slot.dragging = false
                    }
                    // On the card's top edge, over its padding and the gap above, so they cover none of its content; on a
                    // pill of their own so they read on any wallpaper (flat chrome draws its keys without a fill).
                    Rectangle {
                        visible: desk.editing
                        anchors.fill: cardKeys
                        anchors.margins: -3
                        radius: height / 2
                        color: Theme.panel
                        border.width: Theme.outlineW > 0 ? Theme.outlineW : 1
                        border.color: Theme.outlineW > 0 ? Theme.line : Theme.outline
                    }
                    Row {
                        id: cardKeys
                        visible: desk.editing
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: -Math.round(height / 2)
                        anchors.rightMargin: Theme.pad
                        spacing: Theme.xs
                        // Return on a key is Done, as on the card (I196): the keys hand it on.
                        IconButton {
                            icon: "arrow_upward"; glyph: "↑"
                            a11y: I18n.tr("frontend.desktop.edit.up")
                            enabled: !desk.orderLocked && slot.index > 0
                            acceptsReturn: false
                            onClicked: desk.moveCard(cards.side, slot.index, slot.index - 1)
                        }
                        IconButton {
                            icon: "arrow_downward"; glyph: "↓"
                            a11y: I18n.tr("frontend.desktop.edit.down")
                            enabled: !desk.orderLocked && slot.index < cards.model.count - 1
                            acceptsReturn: false
                            onClicked: desk.moveCard(cards.side, slot.index, slot.index + 1)
                        }
                        IconButton {
                            icon: slot.wanted ? "visibility" : "visibility_off"; glyph: slot.wanted ? "◉" : "◌"
                            a11y: I18n.tr(slot.wanted ? "frontend.desktop.edit.hide" : "frontend.desktop.edit.show")
                            lit: slot.wanted
                            enabled: !slot.locked
                            acceptsReturn: false
                            onClicked: desk.toggleShown(slot.cid)
                        }
                        // W44 (point 15): to the other column (its arrow points there); after the eye, so the Tab path to the eye stays.
                        IconButton {
                            objectName: "desk-side:" + slot.cid
                            icon: cards.side === "left" ? "arrow_forward" : "arrow_back"
                            glyph: cards.side === "left" ? "→" : "←"
                            a11y: I18n.tr(cards.side === "left" ? "frontend.desktop.edit.to_right" : "frontend.desktop.edit.to_left")
                            enabled: !desk.orderLocked
                            acceptsReturn: false
                            onClicked: desk.moveSide(cards.side, slot.index)
                        }
                    }
                    // A hidden card says so in words, not by its dimming alone.
                    Rectangle {
                        visible: desk.editing && !slot.wanted
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.leftMargin: Theme.pad
                        anchors.topMargin: -height / 2
                        width: hiddenText.implicitWidth + 2 * Theme.gap
                        height: hiddenText.implicitHeight + 4
                        radius: height / 2
                        color: Theme.selected
                        border.width: Theme.outlineW > 0 ? Theme.outlineW : 0
                        border.color: Theme.line
                        Text {
                            id: hiddenText
                            anchors.centerIn: parent
                            color: Theme.fgOnSelected
                            font.pixelSize: Theme.fsCaption
                            font.weight: Theme.wBold
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.tr("frontend.desktop.edit.hidden")
                        }
                    }
                }
            }
        }
    }

    Component { id: cClock; ClockCard {} }
    Component { id: cCalendar; CalendarCard {} }
    Component { id: cMedia; MediaCard {} }
    Component { id: cWeather; WeatherCard {} }
    Component { id: cMod; ModCard {} }

    // The weather mod's condition codes as Material Symbols names.
    function conditionIcon(code, isDay) {
        switch (code) {
        case "clear": case "mainly_clear": return isDay === false ? "clear_night" : "sunny"
        case "partly_cloudy": return isDay === false ? "partly_cloudy_night" : "partly_cloudy_day"
        case "overcast": return "cloud"
        case "fog": return "foggy"
        case "drizzle": case "freezing_drizzle": case "rain": case "freezing_rain": case "showers": return "rainy"
        case "snow": case "snow_grains": case "snow_showers": return "weather_snowy"
        case "thunder": case "thunder_hail": return "thunderstorm"
        default: return "cloud"
        }
    }
}
