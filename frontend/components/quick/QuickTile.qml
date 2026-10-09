import QtQuick
import "../../core"
import ".."

// A quick-settings tile (W13, docs/ux/quick-settings.md): 160 x 56 px. The main zone toggles (or opens the page, when the
// tile has no switch); the arrow zone opens the drill-down page in the same card. The subtitle is the value in effect.
// States: off, on, connecting (glyph swap, "Connecting…"), failed (the reason in red; Enter or a click retries),
// unavailable (dim, the reason), forced (inert, who sets the value). Keys: Enter and Space toggle or open, Right opens
// the page; QuickPanel's grid moves the focus with the arrows.
Item {
    id: tile
    width: 160
    height: 56
    property string glyph: ""
    property string title: ""
    property string value: ""        // the value in effect, as text
    property bool on: false
    property bool toggles: true
    property string reason: ""       // unavailable: why, short ("" when available)
    property string forcedBy: ""     // forced: who sets the value ("" when it is not forced)
    property var req: null           // the Request that changes `on`; null when the tile has no switch
    property string pendingText: ""
    property bool hasPage: true
    signal pageRequested()

    readonly property bool inert: reason !== "" || forcedBy !== ""
    readonly property bool connecting: req !== null && req.pending
    readonly property bool failed: req !== null && req.failure !== ""
    readonly property bool lit: on && reason === "" && !failed
    readonly property string subtitle: reason !== "" ? reason
        : forcedBy !== "" ? I18n.tr("island.quick.forced").replace("{by}", forcedBy)
        : failed ? req.failure
        : connecting ? pendingText
        : value

    function activate() {
        if (connecting) return
        if (inert) { if (hasPage) pageRequested(); return }
        if (failed) req.retry()
        else if (toggles && req !== null) req.begin(!on)
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
    Accessible.name: tile.title
    Accessible.description: tile.subtitle
    Accessible.checkable: toggles && !inert
    Accessible.checked: on

    Rectangle {
        id: face
        anchors.fill: parent
        radius: Theme.rSm + 2
        color: tile.lit ? Qt.alpha(Theme.accent, 0.22) : Theme.containerHigh
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
        color: tile.lit ? Theme.accent : Theme.surface
        Text {
            anchors.centerIn: parent
            color: tile.lit ? Theme.fgOnAccent : (tile.failed ? Theme.error : Theme.fg)
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
            text: tile.title
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: tile.failed ? Theme.error : Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: tile.subtitle
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
