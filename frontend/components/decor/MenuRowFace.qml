import QtQuick
import "../../core"

// MenuRowFace (W53 integration, contract row 591): a menu row's background as the look draws it, beside the caller's
// own. A caller keeps its own highlight and separator line where the look leaves them (`ownHighlight`: no menu part and
// a capsule highlight; `ownSeparator`: no menu part and a line separator — today's rows, pixel-identical) and lays this
// under the row's content: the look's menu part (MenuStyle.rowBackground, contract menu/MenuRowBase.qml), else a full-
// width band (`bar`, 9x/XP), a band inside the menu's margin (`inset`), an etched separator (a dark over a light line) or
// none (`space`). Nothing is made while the caller draws its own (one Loader, inactive).
Item {
    id: f
    property bool highlighted: false
    property bool separator: false
    property bool enabled: true
    property bool checked: false
    // Where an `inset` band and a separator stop, from the row's sides.
    property real margin: Theme.pad
    MenuStyle { id: ms }
    readonly property bool ownHighlight: !ms.has && ms.highlight === "capsule"
    readonly property bool ownSeparator: !ms.has && ms.separator === "line"
    readonly property bool drawn: separator ? !ownSeparator : (!ownHighlight && (highlighted || ms.has))
    // The row's text on this face: the selection's ink on a band, else the caller's own.
    // (A look's `menu.on` wins on its band — a part's or ours — row 598.)
    function ink(own) {
        if (!highlighted || separator || ownHighlight) return own
        return ms.has ? ms.ink(own) : ms.ink(Theme.fgOnSelected)
    }

    Loader {
        anchors.fill: parent
        active: f.drawn && ms.has
        source: active ? ms.rowBackground : ""
        onLoaded: {
            item.highlighted = Qt.binding(function () { return f.highlighted })
            item.separator = Qt.binding(function () { return f.separator })
            item.enabled = Qt.binding(function () { return f.enabled })
            item.checked = Qt.binding(function () { return f.checked })
        }
    }
    Loader {
        anchors.fill: parent
        active: f.drawn && !ms.has
        sourceComponent: f.separator ? sep : band
    }
    Component {
        id: band
        Rectangle {
            x: ms.highlight === "inset" ? f.margin / 2 : 0
            width: parent.width - 2 * x
            height: parent.height
            radius: ms.radius(0)
            color: ms.fill(Theme.selected)
        }
    }
    Component {
        id: sep
        Item {
            readonly property real w: Theme.crisp(1, Screen.devicePixelRatio)
            visible: ms.separator === "etched"
            Rectangle {
                x: f.margin; width: parent.width - 2 * f.margin; height: parent.w
                y: Math.round(parent.height / 2) - parent.w
                color: Theme.bevelDark2
            }
            Rectangle {
                x: f.margin; width: parent.width - 2 * f.margin; height: parent.w
                y: Math.round(parent.height / 2)
                color: Theme.bevelLight
            }
        }
    }
}
