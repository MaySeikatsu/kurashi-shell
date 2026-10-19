import QtQuick
import "../core"

// A contribution point of a core view (K28, docs/ux/COMPOSITION.md §3). Shows the `ready` contributions that
// runtime.slots lists for `slot`, one ModLoader each, in the given layout. Nothing contributed: the host is hidden
// and takes no space (no spacing, no placeholder). Something contributed: the hosting card grows with it. The host
// lives exactly as long as its view, so runtime.slots is watched only while that view is on screen (Ma).
// layout: column (a list), row (side by side), flow (tiles that wrap), stack (each contribution fills the host,
// a backdrop; the parent sizes the host, so it does not set its own height), cells (W18: the host lays nothing out;
// its caller places one `cell` per contribution in its own grid, each cellWidth x cellHeight and clipped to it).
Item {
    id: host
    property string slot: ""
    property string layout: "column"
    property real cellWidth: 0
    property real cellHeight: 0

    // One grid cell per contribution (layout "cells"): a ModLoader in an Item of the cell's size, clipped to it, so a
    // contribution that is not a tile is drawn inside its cell and never grows the grid. `tile` is the loaded root.
    readonly property Component cell: Component {
        Item {
            id: cellItem
            required property var modelData
            width: host.cellWidth
            height: host.cellHeight
            clip: true
            readonly property var tile: loader.item
            ModLoader {
                id: loader
                anchors.fill: parent
                url: cellItem.modelData.qml
            }
        }
    }

    Watch { doc: "runtime.slots" }
    // Changes only with runtime.slots itself, so the Repeater is not reset by other documents.
    readonly property var slotsDoc: Store.docs["runtime.slots"]
    readonly property var entries: {
        var list = (slotsDoc && slotsDoc[slot]) || []
        return list.filter(function (c) { return c.ready === true && typeof c.qml === "string" && c.qml !== "" })
    }
    visible: entries.length > 0
    implicitWidth: body.implicitWidth
    implicitHeight: body.implicitHeight
    // Sized by its content, unless it is a backdrop that its parent sizes (anchors).
    Binding { target: host; property: "height"; value: body.implicitHeight; when: host.layout !== "stack" }

    Loader {
        id: body
        width: host.width
        height: host.layout === "stack" ? host.height : implicitHeight
        sourceComponent: host.layout === "cells" ? null : host.layout === "row" ? rowC : host.layout === "flow" ? flowC
            : host.layout === "stack" ? stackC : columnC
    }
    Component {
        id: columnC
        Column {
            width: body.width
            spacing: Theme.gap
            Repeater {
                model: host.entries
                delegate: contribution
            }
        }
    }
    Component {
        id: rowC
        Row {
            spacing: Theme.gap
            Repeater {
                model: host.entries
                delegate: contribution
            }
        }
    }
    Component {
        id: flowC
        Flow {
            width: body.width
            spacing: Theme.gap
            Repeater {
                model: host.entries
                delegate: contribution
            }
        }
    }
    Component {
        id: stackC
        Item {
            width: body.width
            height: body.height
            Repeater {
                model: host.entries
                delegate: ModLoader {
                    required property var modelData
                    anchors.fill: parent
                    url: modelData.qml
                }
            }
        }
    }
    // One contribution: its file. A list takes the host's width; a row or tiles take what the component asks for.
    Component {
        id: contribution
        ModLoader {
            required property var modelData
            url: modelData.qml
            width: host.layout === "column" ? host.width : implicitWidth
            height: implicitHeight
        }
    }
}
