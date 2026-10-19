import QtQuick
import "../../core"
import ".."

// A quick-settings tile (W13, docs/ux/quick-settings.md; the W15 size contract, CONTRACT-CHANGE row 76): the one tile of the
// card, core or a mod's `quick.tiles` contribution. Its implicit size is 160 x 56 px, so a host lays it out at that size,
// and its props are `glyph`, `label` and `subtitle` (the value in effect). The main zone toggles (or opens the page, when
// the tile has no switch); a tile with `acts` runs its one-step action instead (`activated`, e.g. wallpaper next); the arrow
// zone opens the drill-down page in the same card. The grid sizes a contribution to its cell (W18, docs/ux/COMPOSITION.md §5).
// States: off; on (a tonal container with an accent glyph); connecting (glyph swap, "Connecting…"); failed (the reason in
// red and a solid badge, the one state that asks for attention; Enter or a click retries); unavailable (dim, the reason);
// forced (inert, who sets the value). Keys: Enter and Space toggle or open, Right opens the page; QuickPanel's grid moves
// the focus with the arrows.
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

    // The on state's colours are component tokens (quick.tile.on.*, I51) when the theme document has them; without them
    // the tonal look below is what the tile has always drawn.
    readonly property color onBg: Theme.color("quick.tile.on.bg", Qt.alpha(Theme.accent, 0.22))
    readonly property color onBadge: Theme.color("quick.tile.on.badge", Qt.alpha(Theme.accent, 0.3))
    readonly property color onFg: Theme.color("quick.tile.on.fg", Theme.accent)

    function activate() {
        if (connecting) return
        if (inert) { if (hasPage) pageRequested(); return }
        if (failed) req.retry()
        else if (toggles && req !== null) req.begin(!on)
        else if (acts) activated()
        else if (hasPage) pageRequested()
    }

    activeFocusOnTab: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Right && hasPage) {
            tile.pageRequested()
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

    Rectangle {
        id: face
        anchors.fill: parent
        radius: Theme.rSm + 2
        color: tile.lit ? tile.onBg : Theme.containerHigh
        border.width: tile.failed ? 1 : 0
        border.color: Theme.error
        opacity: tile.reason !== "" ? 0.5 : 1
    }
    Rectangle {
        id: badge
        x: 8
        y: (tile.height - height) / 2
        width: 28
        height: 28
        radius: 14
        // Tonal when on (accent at low alpha, as the container), solid only for the failed state (I51).
        color: tile.failed ? Theme.error : (tile.lit ? tile.onBadge : Theme.surface)
        Text {
            anchors.centerIn: parent
            color: tile.failed ? Theme.surface : (tile.lit ? tile.onFg : Theme.fg)
            font.pixelSize: Theme.fs + 2
            font.family: Theme.fam(text, Theme.families)
            text: tile.failed ? "↻" : (tile.connecting ? "…" : tile.glyph)
        }
    }
    Column {
        x: badge.x + badge.width + 8
        width: arrow.x - x - 4
        anchors.verticalCenter: parent.verticalCenter
        Text {
            width: parent.width
            elide: Text.ElideRight
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: tile.label
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: tile.failed ? Theme.error : Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: tile.shownSubtitle
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
        Text {
            anchors.centerIn: parent
            color: Theme.dim
            font.pixelSize: Theme.fs + 4
            font.family: Theme.fam(text, Theme.families)
            text: "›"
        }
        MouseArea {
            anchors.fill: parent
            onClicked: tile.pageRequested()
        }
    }
    MouseArea {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: arrow.left
        onClicked: tile.activate()
    }
    FocusRing {
        anchors.fill: parent
        shown: tile.activeFocus
        corner: face.radius
    }
}
