import QtQuick
import "../core"

// One section of a page as a card (K48 (5), I104; DMS `SettingsCard` + `SettingsGroup`, Noctalia's section boxes,
// Caelestia's dashboard cards): the section's icon and title on top, its rows inside. Drawn from tokens only (rule 4): the
// container fill, an outline in the chrome's ink when the chrome has one (keycap, line) or a hairline, and the hard shadow
// under keycap chrome. `header` false (search results) leaves the title to each row's breadcrumb.
Item {
    id: c
    property string title: ""
    property string icon: ""
    property bool header: true
    default property alias body: rows.data

    implicitHeight: face.height + Theme.shadowDy
    Accessible.role: Accessible.Grouping
    Accessible.name: c.title

    // The hard shadow along the shadow vector (K67, docs/ux/shadows.md): none at strength 0 or under flat and line chrome.
    RoundBox {
        visible: Theme.sinkX !== 0 || Theme.sinkY !== 0
        x: Theme.sinkX
        y: Theme.sinkY
        width: face.width
        height: face.height
        radius: face.radius
        color: Theme.line
    }
    RoundBox {
        id: face
        width: c.width
        height: col.implicitHeight + 2 * Theme.pad
        radius: Theme.rLg
        color: Theme.container
        border.width: Theme.outlineW > 0 ? Theme.outlineW : 1
        border.color: Theme.outlineW > 0 ? Theme.line : Theme.containerHigh
        // The material on the card's fill, under its rows (K63), inside its outline.
        Loader {
            anchors.fill: parent
            anchors.margins: face.border.width
            active: Theme.surfaceRelief
            sourceComponent: Relief { radius: Math.max(0, face.radius - face.border.width) }
        }
        Column {
            id: col
            x: Theme.pad
            y: Theme.pad
            width: parent.width - 2 * Theme.pad
            Row {
                visible: c.header
                spacing: Theme.gap
                bottomPadding: Theme.gap / 2
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    visible: Theme.iconFamily !== "" && c.icon !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.iconFamily
                    font.pixelSize: Theme.fs + 7
                    font.variableAxes: ({ "FILL": 1 })
                    color: Theme.accent
                    text: c.icon
                }
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    font.pixelSize: Theme.fs + 1
                    font.weight: Theme.wBold
                    font.family: Theme.fam(text, Theme.families)
                    text: c.title
                }
            }
            Column {
                id: rows
                width: parent.width
            }
        }
    }
}
