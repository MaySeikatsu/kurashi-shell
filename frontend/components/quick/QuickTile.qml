import QtQuick
import Quickshell
import "../../core"
import ".."

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
Item {
    id: tile
    implicitWidth: 160
    implicitHeight: 56
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
        anchors.fill: parent
        radius: Theme.rFull
        fill: tile.lit ? tile.onBg : Theme.containerHigh
        pressed: (mainArea.pressed || arrowArea.pressed) && !tile.connecting
        opacity: tile.reason !== "" ? 0.5 : 1
        // The failed state: a ring in the error colour over the face, the one state that asks for attention.
        Rectangle {
            visible: tile.failed
            anchors.fill: parent
            radius: height / 2
            color: "transparent"
            border.width: 2
            border.color: Theme.error
        }
        Block {
            id: badge
            x: 5
            y: Math.round((face.faceH - 2 * face.inset - height) / 2)
            width: 30
            height: 30
            radius: Theme.rFull
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
            width: face.width - 2 * face.inset - x - arrow.width
            anchors.verticalCenter: parent.verticalCenter
            Text {
                width: parent.width
                elide: Text.ElideRight
                color: tile.lit ? tile.onFg : Theme.fg
                font.pixelSize: Theme.fs
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                text: tile.label
            }
            Text {
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
    // The arrow zone: the drill-down. Its own hit area, so a click here never toggles.
    Item {
        id: arrow
        width: 22
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        visible: tile.hasPage
        Icon {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -Theme.shadowDy / 2
            name: "chevron_right"
            glyph: "›"
            size: 18
            color: tile.lit ? tile.onFg : Theme.dim
        }
        MouseArea {
            id: arrowArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: tile.pageRequested()
        }
    }
    MouseArea {
        id: mainArea
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: arrow.left
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) tile.secondary()
            else tile.activate()
        }
    }
    FocusRing {
        width: parent.width
        height: face.faceH
        shown: tile.activeFocus
        corner: height / 2
    }
}
