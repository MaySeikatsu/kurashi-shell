import QtQuick

// One metric in the panel: label, value, a 60-sample sparkline and the lines of detail (docs/ux/sysmon.md, "Panel").
// The width is the grid's cell (two cells fill the 328 px content); the detail wraps, so a long source or a list of
// paths searched never pushes the tile past its cell. The level comes from the daemon and is shown by a glyph as
// well as by colour (never colour alone).
Rectangle {
    id: tile
    required property var theme
    property string label: ""
    property string value: "–"
    property string detail: ""
    property var history: []
    property real ceiling: 100
    property string level: "normal"
    property string sparkDescription: ""

    readonly property string glyph: level === "critical" ? "■ " : (level === "activity" ? "▲ " : "")
    readonly property color ink: level === "critical" ? tile.theme.error : tile.theme.fg

    implicitWidth: 160
    height: column.implicitHeight + tile.theme.pad * 2
    radius: tile.theme.rSm
    color: tile.theme.container
    border.width: level === "normal" ? 0 : 1
    border.color: level === "critical" ? tile.theme.error : tile.theme.outline
    clip: true
    Accessible.role: Accessible.Pane
    Accessible.name: label + ", " + glyph + value + (detail !== "" ? ", " + detail : "")

    Column {
        id: column
        x: tile.theme.pad
        y: tile.theme.pad
        width: tile.width - tile.theme.pad * 2
        spacing: tile.theme.xs

        Text {
            width: parent.width
            text: tile.label
            color: tile.theme.dim
            elide: Text.ElideRight
            font.pixelSize: tile.theme.fsCaption
            font.family: tile.theme.fam(text, tile.theme.families)
        }
        Text {
            width: parent.width
            text: tile.glyph + tile.value
            color: tile.ink
            elide: Text.ElideRight
            font.pixelSize: tile.theme.fsTitle
            font.family: tile.theme.fam(text, tile.theme.families)
            font.features: ({"tnum": 1})
        }
        Spark {
            width: parent.width
            height: 28
            theme: tile.theme
            values: tile.history
            ceiling: tile.ceiling
            stroke: tile.level === "critical" ? tile.theme.error : tile.theme.dim
            description: tile.sparkDescription
        }
        Text {
            width: parent.width
            visible: tile.detail !== ""
            text: tile.detail
            color: tile.theme.dim
            wrapMode: Text.WordWrap
            font.pixelSize: tile.theme.fsCaption
            font.family: tile.theme.fam(text, tile.theme.families)
        }
    }
}
