import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"
import "../components/launcher"

// Launcher (M5): centred overlay with exclusive keyboard focus while open. The daemon owns the
// open state (runtime.ui.launcher), the index, ranking and launching; this only renders results
// of `query launcher` and sends `launcher.launch` / `ui.close`.
//
// Prefix modes (K44, I126, W26; docs/ux/launcher.md): `:` emoji as a grid (8 a row, arrows move in two dimensions,
// recent first), `;` the clipboard history (image thumbnails, pins, Shift+Delete removes, a "clear history" row with a
// confirm), `>` commands, `?` the keybind cheat sheet (also action `launcher.keys`: `runtime.ui.launcher_query`).
//
// Same idle discipline as Stage (K16): permanently mapped but transparent, input-less and
// focus-less while hidden, so it renders 0 frames. Typing never animates: the result list is replaced, the highlight
// just moves.
//
// W34 (docs/ux/motion.md): under a top or bottom bar the launcher grows out of the island pill as one shape (BarMorph:
// the island's MorphShape, two springs, the liquid neck at the bar's edge, the pill's face in its head) and folds back
// into it; the card then hangs under the bar's centre and the window covers the bar's strip above it (margin 0, the
// shape's box; K16: its size only, never the output's). Without one (a side bar, no bar) it stays centred on the output
// and slides in, as before.
PanelWindow {
    id: lp

    readonly property var ui: Store.docs["runtime.ui"] || ({})
    readonly property bool want: ui.launcher === true
    // The text `launcher.keys` (or a later caller) opens the launcher with; "" for a plain open.
    readonly property string openQuery: ui.launcher_query || ""
    readonly property string mode: {
        var c = field.text.charAt(0)
        return c === ":" ? "emoji" : (c === ";" ? "clip" : (c === "?" ? "keys" : "apps"))
    }
    // K59: this window's tile set, shared by its reliefs, and the pointer light's sensor. K61: the card's carry while it
    // slides in (`texture.sheet = carried`; its scale is not carried); 0 in the morph, whose shape carries its own.
    property var tileSheet: tilesLoader.item
    readonly property point sheetCarry: morph.carry
    Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
    LightSense {}
    readonly property int rowH: 48
    readonly property int maxRows: 7
    readonly property int cols: 8          // emoji grid
    readonly property int cellH: 60
    readonly property int gridRows: 5
    // The list follows its results: as tall as its rows, within one row and the mode's most.
    readonly property int maxListH: mode === "keys" ? 432 : (mode === "clip" ? 396 : maxRows * rowH)
    readonly property int contentH: {
        var h = 0
        for (var i = 0; i < results.length && h < maxListH; i++) h += heightOf(results[i])
        return h
    }
    readonly property int listH: mode === "emoji"
        ? Math.max(1, Math.min(Math.ceil(results.length / cols), gridRows)) * cellH
        : Math.max(rowH, Math.min(contentH, maxListH))
    readonly property bool footer: mode !== "apps"
    readonly property bool shown: morph.shown
    property var results: []
    property int sel: 0
    property string err: ""     // translated failure line above the list; "" when there is none
    property bool confirmClear: false   // the "clear history" row asked once; Enter again clears
    // Clipboard thumbnails asked for during this open (id → path, "!" = none), and which ids were asked.
    property var thumbs: ({})
    property var asked: ({})
    property var scr: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null   // latched on open so the card never jumps outputs

    function heightOf(r) {
        switch (r.kind) {
        case "keygroup": return 30
        case "key": return 38
        case "clip": return r.image ? 72 : 58
        default: return rowH
        }
    }
    function focusedScreen() {
        var o = (Store.docs["svc.workspaces"] && Store.docs["svc.workspaces"].outputs) || {}
        var s = Quickshell.screens
        for (var i = 0; i < s.length; i++) {
            var l = o[s[i].name] || []
            for (var j = 0; j < l.length; j++)
                if (l[j].focused) return s[i]
        }
        return s.length > 0 ? s[0] : null
    }
    // A failure carries a kind (invalid, unavailable, internal, or the Store's own) and a message. A message that is
    // one of our i18n keys (the clipboard's refusals) is shown translated; any other message is English and never
    // shown: the kind picks a translated line, unknown kinds the generic one.
    function errorText(e) {
        if (e.msg) {
            var m = I18n.tr(e.msg)
            if (m !== e.msg) return m
        }
        var k = "surfaces.launcher.error." + (e.kind || "failed")
        var t = I18n.tr(k)
        return t !== k ? t : I18n.tr("surfaces.launcher.error.failed")
    }
    function selectable(i) { return i >= 0 && i < results.length && results[i].kind !== "keygroup" }
    // The first selectable row from `i` going `d` (±1), else the other way, else 0.
    function settle(i, d) {
        var j = i
        while (j >= 0 && j < results.length && !selectable(j)) j += d
        if (selectable(j)) return j
        j = i
        while (j >= 0 && j < results.length && !selectable(j)) j -= d
        return selectable(j) ? j : 0
    }
    function move(d) {
        if (results.length === 0) return
        if (mode === "emoji") {
            var g = sel + d
            if (g >= 0 && g < results.length) sel = g
            else if (d > 1) sel = results.length - 1     // Down on the last row: the last cell
            return
        }
        var j = sel + d
        while (j >= 0 && j < results.length && !selectable(j)) j += d > 0 ? 1 : -1
        if (selectable(j)) sel = j
    }
    function run(q, keep) {
        Store.query("launcher", q, function (items, e) {
            if (!lp.want) return
            var old = lp.sel
            lp.results = items || []
            lp.sel = lp.settle(keep ? Math.min(old, lp.results.length - 1) : 0, 1)
            lp.err = e ? lp.errorText(e) : ""
        })
    }
    function requestThumb(id) {
        if (!want || asked[id]) return
        asked[id] = true
        Store.act("launcher.clip.thumb", { id: id }, function (done, e) {
            if (!lp.want) return
            var t = Object.assign({}, lp.thumbs)
            t[id] = done && done.data && done.data.path ? done.data.path : "!"
            lp.thumbs = t
        })
    }
    // Clipboard keys: Shift+Delete removes the selected entry (a pin: unpins it), Ctrl+P pins or unpins it.
    function clipAct(action) {
        var r = results[sel]
        if (!r || r.kind !== "clip") return
        Store.act(action, { id: r.id }, function (done, e) {
            if (e) { lp.err = lp.errorText(e); return }
            lp.err = ""
            lp.run(field.text, true)
        })
    }
    function launch() {
        if (sel < 0 || sel >= results.length) return
        var r = results[sel]
        if (r.kind === "clipclear") {
            if (!confirmClear) { confirmClear = true; return }
            confirmClear = false
            Store.act("launcher.clip.clear", {}, function (done, e) {
                if (e) { lp.err = lp.errorText(e); return }
                lp.run(field.text)
            })
            return
        }
        if (!r.id) return
        var id = r.id
        // A `>` command may open a panel of its own (quick settings, the session keys): the launcher closes first.
        if (id.indexOf("cmd:") === 0) {
            Store.act("ui.close", {}, function () { Store.act("launcher.launch", { id: id }) })
            return
        }
        Store.act("launcher.launch", { id: id }, function (done, e) {
            // Close only once the app is up: a failure stays open with its reason.
            if (e) { lp.err = lp.errorText(e); return }
            Store.act("ui.close")
        })
    }
    onSelChanged: confirmClear = false
    onModeChanged: confirmClear = false

    screen: scr
    BarConfig { id: bars; screen: lp.scr }
    // While the shape is out under a top or bottom bar, one vertical edge anchored (the compositor centres the surface
    // horizontally, so the shape's box is centred on the bar); none otherwise (idle, or no such bar): centred on the output.
    anchors { top: morph.layout && !bars.atBottom; bottom: morph.layout && bars.atBottom }
    implicitWidth: morph.width
    implicitHeight: morph.height
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: want ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "kurashi-launcher"
    color: "transparent"
    mask: shown ? cardRegion : emptyRegion
    // The shape changes size every frame of its morph: blur only behind the card at rest.
    BackgroundEffect.blurRegion: shown && morph.settled ? cardRegion : emptyRegion
    Region { id: cardRegion; item: morph.cardItem }
    Region { id: emptyRegion }

    onWantChanged: {
        if (want) {
            scr = focusedScreen()
            results = []; sel = 0; err = ""; confirmClear = false
            thumbs = ({}); asked = ({})
            // Setting the text runs its query (onTextChanged); an unchanged text needs the run here.
            if (field.text === openQuery) run(openQuery)
            else field.text = openQuery
            field.cursorPosition = field.text.length
            field.forceActiveFocus()
        } else {
            // Ma: a focused field keeps its cursor blinking, and the hidden window drew twice a second for it (before W34
            // too): the field lets go of the focus when the launcher closes.
            field.focus = false
        }
    }
    // `launcher.keys` while the launcher is already open: switch to the cheat sheet.
    onOpenQueryChanged: if (want && openQuery !== "" && field.text !== openQuery) {
        field.text = openQuery
        field.cursorPosition = field.text.length
    }
    BarMorph {
        id: morph
        outName: lp.scr ? lp.scr.name : ""
        onBar: bars.atTop || bars.atBottom
        flip: bars.atBottom
        open: lp.want
        cardW: card.width
        cardH: card.height
        slide: 12
        slideScale: 0.96
        onHidden: { lp.results = []; lp.thumbs = ({}) }

        // The card's content. In the morph the shape is its chrome; sliding in, it is a Block (K42, K45): a flat panel with a
        // hairline, a keycap panel with an ink outline and hard shadow, a soft glass panel with a rim and a drop shadow, or a
        // panel outlined in ink (line).
        Item {
            id: card
            width: 600
            readonly property real inset: Theme.outlineW + Theme.ringW
            readonly property int footH: lp.footer ? Theme.gap + 18 : 0
            height: 2 * Theme.pad + 2 * inset + 44 + Theme.gap + (lp.err !== "" ? errRow.height + Theme.gap : 0) + lp.listH
                + footH + (morph.morph ? 0 : Theme.shadowDy)
            Block {
                visible: !morph.morph
                anchors.fill: parent
                radius: Theme.rLg + 4
                fill: Theme.panel
                flatBorder: Theme.outline
                // K62: the pen's salt for the card's outline (a surface knows who it is; its place moves as it opens).
                penSeed: 0x1A0C
            }

            Block {
                id: box
                x: Theme.pad + card.inset
                y: Theme.pad + card.inset
                width: card.width - 2 * x
                height: 44
                radius: Theme.rFull
                ringScale: 0
                softScale: 0
                fill: Theme.surface
                flatBorder: field.activeFocus ? Theme.accent : Theme.outline
                penSeed: 0x1A0D
                Icon {
                    id: searchIcon
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    name: lp.mode === "emoji" ? "mood" : (lp.mode === "clip" ? "content_paste"
                        : (lp.mode === "keys" ? "keyboard" : "search"))
                    glyph: "⌕"
                    color: Theme.dim
                    size: Theme.fsTitle + 4
                }
                TextInput {
                    id: field
                    anchors { fill: parent; leftMargin: searchIcon.x + searchIcon.width + 8; rightMargin: 14 }
                    color: Theme.fg
                    font.pixelSize: Theme.fsTitle
                    font.weight: Theme.wMedium
                    font.family: Theme.fam(text, Theme.families)
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    clip: true
                    onTextChanged: if (lp.want) lp.run(text)
                    Keys.onEscapePressed: {
                        if (lp.confirmClear) lp.confirmClear = false
                        else Store.act("ui.close")
                    }
                    Keys.onDownPressed: lp.move(lp.mode === "emoji" ? lp.cols : 1)
                    Keys.onUpPressed: lp.move(lp.mode === "emoji" ? -lp.cols : -1)
                    // In the emoji grid the arrows move across a row; elsewhere they move the text cursor.
                    Keys.onLeftPressed: (event) => { if (lp.mode === "emoji") lp.move(-1); else event.accepted = false }
                    Keys.onRightPressed: (event) => { if (lp.mode === "emoji") lp.move(1); else event.accepted = false }
                    Keys.onReturnPressed: lp.launch()
                    Keys.onEnterPressed: lp.launch()
                    Keys.onPressed: (event) => {
                        var shift = (event.modifiers & Qt.ShiftModifier) !== 0
                        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                        if (lp.mode === "clip" && event.key === Qt.Key_Delete && shift) {
                            lp.clipAct("launcher.clip.delete"); event.accepted = true
                        } else if (lp.mode === "clip" && event.key === Qt.Key_P && ctrl) {
                            lp.clipAct("launcher.clip.pin"); event.accepted = true
                        } else if (event.key === Qt.Key_PageDown) {
                            lp.move(lp.mode === "emoji" ? lp.cols * lp.gridRows : 8); event.accepted = true
                        } else if (event.key === Qt.Key_PageUp) {
                            lp.move(lp.mode === "emoji" ? -lp.cols * lp.gridRows : -8); event.accepted = true
                        }
                    }
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: field.text === "" && field.preeditText === ""
                        color: Theme.dim
                        font: field.font
                        text: I18n.tr("launcher.placeholder")
                    }
                    // The prefix modes, named while the field is empty.
                    Text {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        visible: field.text === "" && field.preeditText === ""
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("launcher.modes")
                    }
                }
            }

            // Failure line above the results (a failed launch or query). The results stay usable.
            Text {
                id: errRow
                visible: lp.err !== ""
                x: Theme.pad + card.inset
                y: box.y + box.height + Theme.gap
                width: card.width - 2 * x
                wrapMode: Text.WordWrap
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: lp.err
            }

            ListView {
                id: list
                visible: lp.mode !== "emoji"
                x: Theme.pad + card.inset
                y: lp.err !== "" ? errRow.y + errRow.height + Theme.gap : box.y + box.height + Theme.gap
                width: card.width - 2 * x
                height: lp.listH
                clip: true
                interactive: false
                // Only the rows on screen exist, so only their thumbnails are asked for (Ma).
                cacheBuffer: 0
                model: lp.mode !== "emoji" ? lp.results : []
                currentIndex: lp.sel
                highlightMoveDuration: 0
                // The selected row's highlight is one tonal block that springs to the row (keycap: outlined).
                highlight: Block {
                    width: list.width
                    height: list.currentItem ? list.currentItem.height - 2 : lp.rowH - 2
                    radius: Theme.rLg
                    ringScale: 0
                    softScale: 0
                    fill: Theme.selected
                    // K62: one line however far it springs (its place changes with the selection).
                    penSeed: 0x1A0E
                    Behavior on y {
                        enabled: lp.shown && Theme.springOn
                        NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot * 0.6 }
                    }
                }
                highlightFollowsCurrentItem: true
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property string kind: modelData.kind || ""
                    readonly property bool isCalc: kind === "calc"
                    // Prefix modes (daemon): `:` emoji, `;` clipboard; a `note` row only explains (an i18n key, no id).
                    readonly property bool isEmoji: kind === "emoji"
                    readonly property bool isNote: kind === "note"
                    // `>` commands (I126) carry their Material icon; the web row searches the query.
                    readonly property bool isCommand: kind === "command"
                    readonly property bool isWeb: kind === "web"
                    // Rows drawn by their own component (W26): a clipboard entry, the clear row, a cheat sheet row.
                    readonly property bool own: kind === "clip" || kind === "clipclear" || kind === "key" || kind === "keygroup"
                    readonly property bool copies: isCalc || isEmoji
                    readonly property bool selected: index === lp.sel
                    width: list.width
                    height: lp.heightOf(modelData)

                    Item {
                        anchors.fill: parent
                        visible: !row.own
                        Item {
                            id: ico
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -Theme.shadowDy / 2
                            width: 30; height: 30
                            property string src: row.kind === "app" && row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
                            Image {
                                id: img
                                anchors.fill: parent
                                source: ico.src
                                sourceSize: Qt.size(60, 60)
                                asynchronous: true
                                visible: ico.src !== "" && status === Image.Ready
                            }
                            // The app's picture: its relief on its own pixels, masked by its alpha (row 285), so a transparent row's
                            // ground does not halo. A fallback tile carries its own relief (below).
                            Loader {
                                active: Theme.texControls && img.visible && !!(Window.window && QsWindow.window && QsWindow.window.tileSheet)
                                anchors.fill: parent
                                sourceComponent: Item {
                                    anchors.fill: parent
                                    ShaderEffectSource {
                                        id: pictureMask
                                        width: parent.width
                                        height: parent.height
                                        sourceItem: img
                                        live: false
                                        x: -100000
                                        y: -100000
                                        readonly property var key: [img.status, img.source, img.width, img.height]
                                        onKeyChanged: scheduleUpdate()
                                        Component.onCompleted: scheduleUpdate()
                                    }
                                    Relief { anchors.fill: parent; radius: 0; mask: pictureMask }
                                }
                            }
                            // Text fallback: initial of the name; a calculation shows its icon.
                            Rectangle {
                                id: fallback
                                anchors.fill: parent
                                visible: !img.visible
                                radius: Theme.rSm
                                color: row.isCalc ? Theme.accent : (row.isEmoji ? "transparent" : Theme.surface)
                                border.width: !row.isEmoji ? Theme.outlineW : 0
                                border.color: Theme.outlineColor
                                Icon {
                                    anchors.centerIn: parent
                                    visible: row.isCalc || row.isNote || row.isCommand || row.isWeb
                                    name: row.isCalc ? "calculate"
                                        : ((row.isCommand || row.isWeb) ? (row.modelData.icon || "bolt") : "info")
                                    glyph: row.isCalc ? "=" : (row.isWeb ? "⌕" : (row.isCommand ? "›" : "i"))
                                    filled: true
                                    color: row.isCalc ? Theme.fgOnAccent : Theme.dim
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: row.isEmoji
                                    font.pixelSize: 24
                                    text: row.modelData.glyph || ""
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: row.kind === "app" || row.kind === "action"
                                    color: Theme.dim
                                    font.pixelSize: Theme.fs
                                    font.weight: Theme.wBold
                                    font.family: Theme.fam(text, Theme.families)
                                    text: (row.modelData.name || "?").charAt(0).toUpperCase()
                                }
                                // K61 (docs/ux/texture.md "Controls"): an opaque fallback tile carries the relief over its glyph,
                                // in a window that shares its sheet (Relief makes its own otherwise). A picture stays flat.
                                Loader {
                                    active: Theme.texControls && fallback.color.a >= 1 && !!(Window.window && QsWindow.window && QsWindow.window.tileSheet)
                                    anchors.fill: parent
                                    anchors.margins: fallback.border.width
                                    sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, fallback.radius - fallback.border.width) }
                                }
                            }
                        }
                        Column {
                            anchors { left: ico.right; leftMargin: Theme.gap + 2; right: hint.left; rightMargin: 8
                                      verticalCenter: ico.verticalCenter }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                wrapMode: row.isNote ? Text.Wrap : Text.NoWrap
                                maximumLineCount: 2
                                color: row.selected ? Theme.fgOnSelected : Theme.fg
                                font.pixelSize: row.isCalc ? Theme.fsTitle + 2 : (row.isNote ? Theme.fs - 1 : Theme.fs)
                                font.weight: row.isCalc || row.selected ? Theme.wBold : Theme.wMedium
                                font.family: Theme.fam(text, Theme.families)
                                text: row.isNote ? I18n.tr(row.modelData.name).replace("{path}", row.modelData.arg || "")
                                    : (row.isWeb ? I18n.tr("launcher.web").replace("{q}", row.modelData.name) : row.modelData.name)
                            }
                            Text {
                                width: parent.width
                                visible: !!row.modelData.generic
                                elide: Text.ElideRight
                                color: Theme.dim
                                font.pixelSize: Theme.fs - 2
                                font.family: Theme.fam(text, Theme.families)
                                text: row.modelData.generic || ""
                            }
                        }
                        // What Enter does on the selected row: launch, or copy a calculation.
                        Text {
                            id: hint
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: ico.verticalCenter }
                            visible: row.selected && !row.isNote
                            color: Theme.dim
                            font.pixelSize: Theme.fsCaption
                            font.family: Theme.fam(text, Theme.families)
                            text: "↵ " + I18n.tr(row.copies ? "launcher.copy"
                                : (row.isCommand ? "launcher.run" : (row.isWeb ? "launcher.search" : "launcher.open")))
                        }
                    }
                    Loader {
                        anchors.fill: parent
                        active: row.kind === "clip"
                        sourceComponent: Component {
                            ClipRow {
                                entry: row.modelData
                                selected: row.selected
                                thumb: row.modelData.thumb || lp.thumbs[row.modelData.id] || ""
                                onWantThumb: lp.requestThumb(row.modelData.id)
                            }
                        }
                    }
                    Loader {
                        anchors.fill: parent
                        active: row.kind === "key" || row.kind === "keygroup"
                        sourceComponent: Component {
                            KeyRow { entry: row.modelData; selected: row.selected }
                        }
                    }
                    // The "clear history" row: once to ask, Enter again to clear (pins stay; DMS's confirm, inline).
                    Item {
                        anchors.fill: parent
                        visible: row.kind === "clipclear"
                        readonly property bool asking: lp.confirmClear && row.selected
                        Icon {
                            id: clearIcon
                            x: 10 + (30 - width) / 2
                            anchors { verticalCenter: parent.verticalCenter; verticalCenterOffset: -Theme.shadowDy / 2 }
                            name: "delete_sweep"
                            glyph: "×"
                            color: parent.asking ? Theme.error : Theme.dim
                        }
                        Text {
                            anchors { left: parent.left; leftMargin: 40 + Theme.gap + 2; right: parent.right; rightMargin: 12
                                      verticalCenter: clearIcon.verticalCenter }
                            elide: Text.ElideRight
                            color: parent.asking ? Theme.error : (row.selected ? Theme.fgOnSelected : Theme.dim)
                            font.pixelSize: Theme.fs
                            font.weight: parent.asking || row.selected ? Theme.wBold : Theme.wMedium
                            font.family: Theme.fam(text, Theme.families)
                            text: (parent.asking ? I18n.tr("launcher.clip.clear_confirm")
                                : I18n.tr((row.modelData.pins || 0) > 0 ? "launcher.clip.clear_pins" : "launcher.clip.clear"))
                                .replace("{n}", row.modelData.count || 0).replace("{p}", row.modelData.pins || 0)
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: row.kind !== "keygroup"
                        onClicked: { lp.sel = row.index; lp.launch() }
                    }
                }
                onCurrentIndexChanged: {
                    // A group's first row also shows its header.
                    if (currentIndex > 0 && lp.results[currentIndex - 1] && lp.results[currentIndex - 1].kind === "keygroup")
                        positionViewAtIndex(currentIndex - 1, ListView.Contain)
                    positionViewAtIndex(currentIndex, ListView.Contain)
                }
            }

            // The emoji grid (`:`): 8 a row, the selected cell a tonal block; its name under the grid.
            GridView {
                id: grid
                visible: lp.mode === "emoji"
                x: list.x
                y: list.y
                width: list.width
                height: lp.listH
                clip: true
                interactive: false
                cacheBuffer: 0
                cellWidth: width / lp.cols
                cellHeight: lp.cellH
                model: lp.mode === "emoji" ? lp.results : []
                currentIndex: lp.sel
                highlightMoveDuration: 0
                highlightFollowsCurrentItem: true
                highlight: Block {
                    width: grid.cellWidth
                    height: grid.cellHeight
                    radius: Theme.rLg
                    ringScale: 0
                    softScale: 0
                    fill: Theme.selected
                    penSeed: 0x1A0F
                }
                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    width: grid.cellWidth
                    height: grid.cellHeight
                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -Theme.shadowDy / 2
                        font.pixelSize: 30
                        text: cell.modelData.glyph || ""
                        Accessible.name: cell.modelData.name || ""
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { lp.sel = cell.index; lp.launch() }
                    }
                }
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)
            }

            // Under the list: the mode's keys (clipboard, cheat sheet), or the selected emoji's name.
            Item {
                visible: lp.footer
                x: Theme.pad + card.inset
                y: list.y + lp.listH + Theme.gap
                width: card.width - 2 * x
                height: 18
                readonly property var cur: lp.results[lp.sel] || null
                Text {
                    id: footLeft
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    width: parent.width - footRight.implicitWidth - 24
                    visible: lp.mode === "emoji"
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.pixelSize: Theme.fsCaption
                    font.weight: Theme.wMedium
                    font.family: Theme.fam(text, Theme.families)
                    text: parent.cur && parent.cur.kind === "emoji"
                        ? parent.cur.name + (parent.cur.recent ? "  ·  " + I18n.tr("launcher.emoji.recent") : "") : ""
                }
                Text {
                    id: footRight
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr(lp.mode === "emoji" ? "launcher.hint.emoji"
                        : (lp.mode === "clip" ? "launcher.hint.clip" : (lp.mode === "keys" ? "launcher.hint.keys" : "")))
                }
            }

            Text {
                anchors { centerIn: lp.mode === "emoji" ? grid : list }
                visible: lp.results.length === 0
                color: Theme.dim
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("launcher.empty")
            }
        }
    }
}
