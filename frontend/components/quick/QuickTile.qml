import QtQuick
import Quickshell
import "../../core"
import ".."
import "../decor"

// A quick-settings tile (W13, docs/ux/quick-settings.md; the W15 size contract, CONTRACT-CHANGE row 76): the one tile of the
// card, core or a mod's `quick.tiles` contribution. Its implicit size is 160 x 56 px, so a host lays it out at that size,
// and its props are `glyph`, `label` and `subtitle` (the value in effect). The main zone toggles (or opens the page, when
// the tile has no switch); a tile with `acts` runs its one-step action instead (`activated`, e.g. wallpaper next); the arrow
// zone opens the drill-down page in the same card. The grid sizes a contribution to its cell (W18, docs/ux/COMPOSITION.md §5).
// States: off; on (the tonal selected pill, its icon filled on an accent badge); connecting (glyph swap, "Connecting…"); failed (the reason in
// red and a solid badge, the one state that asks for attention; Enter or a click retries); unavailable (dim, the reason);
// forced (inert, who sets the value). Keys: Enter and Space toggle or open, Right opens the page; QuickPanel's grid moves
// the focus with the arrows. The secondary action (W37, I86) is a right click on the main zone, or the Menu key: the page
// when the tile has one, else `secondaryRequested` (QuickPanel opens the Settings page that holds the tile's setting). It
// never toggles, so a right click cannot start a recording or a dark mode by accident.
// W42: one hit area for the whole tile (the arrow zone is its right `arrowW` px); the chevron, the focus ring and the failed
// ring are made only while they show. The drawing and the keys are the same as before (tools/bench/block-identity.sh).
Item {
    id: tile
    implicitWidth: 160
    implicitHeight: rows ? rowH : (compact ? btnH + 30 : 56)
    width: implicitWidth
    height: implicitHeight
    property string glyph: ""
    property string label: ""
    property string subtitle: ""     // the value in effect, as text; a reason, forced-by, failure or "Connecting…" shows over it
    property bool on: false
    property bool toggles: true
    property string reason: ""       // unavailable: why, short ("" when available)
    property string forcedBy: ""     // forced: who sets the value ("" when it is not forced)
    property var req: null           // the Request that changes `on`; null when the tile has no switch
    property string pendingText: ""
    property bool hasPage: true
    property bool acts: false        // the main zone runs a one-step action (`activated`) when the tile has no switch
    signal pageRequested()
    signal secondaryRequested()      // a tile with no page: its secondary action goes to the host (Settings, see above)
    signal activated()
    readonly property bool isTile: true   // the grid's arrows move between tiles only (a plain contribution is no tile)

    // The arrow zone's width: the chevron's, reserved with or without a page (the texts keep the same width, W42).
    readonly property real arrowW: compact ? 28 : 22
    // W53.3 (`[decor] tile.radius`): the face's and the badge's corner — a pill (today's) or the look's own (11's 4 px).
    readonly property real corner: Theme.decor("tile.radius", -1) >= 0 ? Theme.decor("tile.radius", -1) : Theme.rFull
    function inArrow(x) { return hasPage && x >= width - arrowW }
    // W53.3 (`[decor] quick.tiles = compact`): 11's tile — a 48 px button with the icon (split by a hairline from the page's
    // chevron when the tile has a page), the accent fill while on, and the label under the button; wide = today's pill.
    readonly property bool compact: Theme.decor("quick.tiles", "wide") === "compact"
    readonly property int btnH: 48
    // W53.5 (`[decor] quick.tiles = rows`): a config screen's row — the look's menu row (its cursor or band while the row
    // has the keyboard or the pointer; MenuRowFace), the label at the left and the value at the right: both words with the
    // chosen one lit (`quick.values = pair`: a 16-bit RPG's "ON  OFF") or the chosen word (`value`: the PS2's System
    // Configuration); a page's chevron after it. Dim while unavailable or forced, the error colour when failed.
    readonly property bool rows: Theme.decor("quick.tiles", "wide") === "rows"
    readonly property bool pair: Theme.decor("quick.values", "value") === "pair"
    MenuStyle { id: rowStyle }
    readonly property int rowH: rowStyle.rowH(40)

    readonly property bool inert: reason !== "" || forcedBy !== ""
    readonly property bool connecting: req !== null && req.pending
    readonly property bool failed: req !== null && req.failure !== ""
    readonly property bool lit: on && reason === "" && !failed
    readonly property string shownSubtitle: reason !== "" ? reason
        : forcedBy !== "" ? I18n.tr("island.quick.forced").replace("{by}", forcedBy)
        : failed ? req.failure
        : connecting ? pendingText
        : subtitle

    // The on state (K42, I51): the tonal `color.selected` and its ink, the icon filled; component tokens quick.tile.on.*
    // win when a theme document has them. (`Theme.onSelected` reads back as black, like onAccent: the token is read here.)
    readonly property color onBg: Theme.color("quick.tile.on.bg", Theme.selected)
    readonly property color onBadge: Theme.color("quick.tile.on.badge", Theme.accent)
    readonly property color onFg: Theme.color("quick.tile.on.fg", Theme.color("color.on_selected", Theme.fg))
    // A Material Symbols name (Icon.qml); `glyph` is the text drawn without the font (and a mod tile's only mark).
    property string icon: ""
    // K61 (docs/ux/texture.md "Controls"): the badge's icon lies under the relief, as the face's own Block relief lies under
    // every control (Block's own badge relief is then left out: one per pixel), in a window that shares its sheet. The
    // drill-down chevron sits outside the face and stays flat.
    readonly property var qsw: Window.window ? QsWindow.window : null
    readonly property bool ownRelief: Theme.texControls && !Theme.texText && badge.fill.a >= 1 && !!(qsw && qsw.tileSheet)

    function activate() {
        if (connecting) return
        if (inert) { if (hasPage) pageRequested(); return }
        if (failed) req.retry()
        else if (toggles && req !== null) req.begin(!on)
        else if (acts) activated()
        else if (hasPage) pageRequested()
    }

    // The secondary action: the page, or the host's fallback for a tile without one. Never nothing (W37, I86).
    function secondary() {
        if (hasPage) pageRequested()
        else secondaryRequested()
    }

    activeFocusOnTab: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Right && hasPage) {
            tile.pageRequested()
            event.accepted = true
        } else if (event.key === Qt.Key_Menu) {
            tile.secondary()
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            tile.activate()
            event.accepted = true
        }
    }
    Accessible.role: Accessible.Button
    Accessible.name: tile.label
    Accessible.description: tile.shownSubtitle
    Accessible.checkable: toggles && !inert
    Accessible.checked: on

    // A keycap pill (Block, K42): it sinks while pressed; flat chrome draws the same pill as a plain fill.
    Block {
        id: face
        visible: !tile.compact && !tile.rows
        anchors.fill: parent
        radius: tile.corner
        fill: tile.lit ? tile.onBg : Theme.containerHigh
        pressed: hit.pressed && !tile.connecting
        opacity: tile.reason !== "" ? 0.5 : 1
        // The failed state: a ring in the error colour over the face, the one state that asks for attention (made only then).
        Loader {
            active: tile.failed
            anchors.fill: parent
            sourceComponent: Rectangle {
                anchors.fill: parent
                radius: Math.min(height / 2, tile.corner)
                color: "transparent"
                border.width: 2
                border.color: Theme.error
            }
        }
        Block {
            id: badge
            x: 5
            y: Math.round((face.faceH - 2 * face.inset - height) / 2)
            width: 30
            height: 30
            radius: tile.corner
            ringScale: 0
            softScale: 0
            relief: !tile.ownRelief
            animate: face.animate
            fill: tile.failed ? Theme.error : (tile.lit ? tile.onBadge : Theme.container)
            Icon {
                anchors.centerIn: parent
                name: tile.failed ? "refresh" : (tile.connecting ? "more_horiz" : tile.icon)
                glyph: tile.failed ? "↻" : (tile.connecting ? "…" : tile.glyph)
                filled: tile.lit
                size: 18
                color: tile.failed ? Theme.surface : (tile.lit ? Theme.fgOnAccent : Theme.fg)
            }
            // The relief over the badge's fill and icon, inside its outline (the outline stays flat, as Block's).
            Loader {
                active: tile.ownRelief
                anchors.fill: parent
                sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, Math.min(badge.radius, badge.face.height / 2) - badge.inset) }
            }
        }
        Column {
            x: badge.x + badge.width + 6
            width: face.width - 2 * face.inset - x - tile.arrowW
            anchors.verticalCenter: parent.verticalCenter
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                width: parent.width
                elide: Text.ElideRight
                color: tile.lit ? tile.onFg : Theme.fg
                font.pixelSize: Theme.fs
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                text: tile.label
            }
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                width: parent.width
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                lineHeight: 0.85
                elide: Text.ElideRight
                color: tile.failed ? Theme.error : (tile.lit ? tile.onFg : Theme.dim)
                opacity: tile.lit && !tile.failed ? 0.8 : 1
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: tile.shownSubtitle
            }
        }
    }
    // The arrow zone: the drill-down's chevron, made only while the tile has a page (its width is `arrowW` either way). The
    // zone is `hit`'s, below, so the chevron takes no click of its own.
    Loader {
        active: tile.hasPage && !tile.compact && !tile.rows
        width: tile.arrowW
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        sourceComponent: Icon {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -Theme.shadowDy / 2
            name: "chevron_right"
            glyph: "›"
            size: 18
            color: tile.lit ? tile.onFg : Theme.dim
        }
    }
    // The compact tile (W53.3): made only under `quick.tiles = compact`. Drawn from tokens: the accent and its ink while on,
    // the control fill with a hairline at rest, the error ring when failed; dim while unavailable or forced (the reason is
    // the tile's accessible description and its page's text, as before).
    Loader {
        active: tile.compact
        anchors.fill: parent
        sourceComponent: Item {
            Rectangle {
                id: cbtn
                width: parent.width
                height: tile.btnH
                radius: tile.corner
                color: tile.lit ? Theme.accent : Theme.containerHigh
                border.width: tile.failed ? 2 : 1
                border.color: tile.failed ? Theme.error : Qt.alpha(Theme.fg, tile.lit ? 0.0 : 0.08)
                opacity: tile.inert ? 0.5 : (hit.pressed ? 0.85 : 1)
                Icon {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: tile.hasPage ? -tile.arrowW / 2 : 0
                    name: tile.connecting ? "sync" : tile.icon
                    glyph: tile.glyph
                    filled: tile.lit
                    size: 18
                    color: tile.lit ? Theme.fgOnAccent : Theme.fg
                }
                // The split: a hairline, then the page's chevron.
                Rectangle {
                    visible: tile.hasPage
                    x: parent.width - tile.arrowW
                    y: 10
                    width: 1
                    height: parent.height - 20
                    color: Qt.alpha(tile.lit ? Theme.fgOnAccent : Theme.fg, 0.2)
                }
                Icon {
                    visible: tile.hasPage
                    x: parent.width - tile.arrowW + (tile.arrowW - width) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron_right"
                    glyph: "›"
                    size: 16
                    color: tile.lit ? Theme.fgOnAccent : Theme.dim
                }
            }
            Text {
                anchors { left: parent.left; right: parent.right; top: cbtn.bottom; topMargin: 6 }
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                color: tile.failed ? Theme.error : Theme.fg
                opacity: tile.inert ? 0.6 : 1
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: tile.label
            }
        }
    }
    Loader {
        active: tile.rows
        anchors.fill: parent
        sourceComponent: Item {
            id: rowItem
            readonly property bool sel: tile.activeFocus || hit.containsMouse
            readonly property color ink: rowFace.ink(tile.failed ? Theme.error : Theme.fg)
            MenuRowFace {
                id: rowFace
                anchors.fill: parent
                highlighted: rowItem.sel
                enabled: !tile.inert
                checked: tile.lit
            }
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                anchors { left: parent.left; leftMargin: Theme.pad + rowStyle.lead; verticalCenter: parent.verticalCenter
                          right: value.left; rightMargin: Theme.gap }
                elide: Text.ElideRight
                color: rowItem.ink
                opacity: tile.inert ? 0.55 : 1
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: tile.label
            }
            Row {
                id: value
                anchors { right: chev.left; rightMargin: tile.hasPage ? Theme.xs : 0; verticalCenter: parent.verticalCenter }
                spacing: Theme.fs
                readonly property bool words: tile.pair && tile.toggles && tile.req !== null && !tile.inert && !tile.failed
                    && !tile.connecting
                Repeater {
                    model: value.words ? [true, false] : []
                    Text {
                        required property bool modelData
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        antialiasing: !Theme.pixelType
                        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                        color: modelData === tile.on ? rowItem.ink : Theme.dim
                        opacity: modelData === tile.on ? 1 : 0.6
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr(modelData ? "island.quick.value.on" : "island.quick.value.off")
                    }
                }
                Text {
                    visible: !value.words
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    width: Math.min(implicitWidth, tile.width * 0.5)
                    elide: Text.ElideRight
                    color: tile.failed ? Theme.error : (tile.lit ? rowItem.ink : Theme.dim)
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: tile.shownSubtitle
                }
            }
            Icon {
                id: chev
                anchors { right: parent.right; rightMargin: Theme.pad; verticalCenter: parent.verticalCenter }
                width: tile.hasPage ? implicitWidth : 0
                visible: tile.hasPage
                name: "chevron_right"
                glyph: "›"
                size: 16
                color: Theme.dim
            }
        }
    }
    // The one hit area (W42, was two): the arrow zone (the right `arrowW` px, with a page) opens the page with either button;
    // the main zone toggles on a left click and takes the secondary action on a right one. A click needs its press and its
    // release in one zone, as the two areas gave: a drag across the seam is no click.
    MouseArea {
        id: hit
        property bool fromArrow: false
        // The whole tile: a tile with no page toggles on its right `arrowW` px too (no dead strip where no chevron
        // shows; row 478, lead).
        anchors.fill: parent
        hoverEnabled: tile.rows
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => { fromArrow = tile.inArrow(mouse.x) }
        onClicked: mouse => {
            var arrowed = tile.inArrow(mouse.x)
            if (arrowed !== fromArrow) return
            if (arrowed) tile.pageRequested()
            else if (mouse.button === Qt.RightButton) tile.secondary()
            else tile.activate()
        }
    }
    // The keyboard focus ring (DESIGN-SYSTEM §7): made only while the tile holds the focus, in the same place (W42).
    Loader {
        active: tile.activeFocus && !(tile.rows && rowStyle.has)
        width: parent.width
        height: tile.compact ? tile.btnH : face.faceH
        sourceComponent: FocusRing {
            anchors.fill: parent
            shown: true
            corner: tile.compact ? tile.corner : height / 2
        }
    }
}
