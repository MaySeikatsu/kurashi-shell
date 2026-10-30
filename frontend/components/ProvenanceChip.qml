import QtQuick
import "../core"

// Shōjiki (rule 2): renders a Provenanced value {value, source, forced_by?, reason?}.
// Shows the value with a source badge. When forced_by is set the value is NOT in the user's
// control: it is dimmed and a padlock marks it. No strikethrough, which reads as "not in effect".
// The reason shows on hover and on keyboard focus; the chip takes Tab focus when it has a reason.
Item {
    id: p
    property var prov: ({})
    readonly property bool forced: prov.forced_by !== undefined && prov.forced_by !== null
    readonly property string note: forced
        ? I18n.tr("frontend.prov.forced_by") + " " + prov.forced_by + (prov.reason ? " · " + prov.reason : "")
        : (prov.reason ? prov.reason : "")

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    activeFocusOnTab: note !== ""
    Accessible.role: Accessible.StaticText
    Accessible.name: String(prov.value ?? "")
    Accessible.description: note

    Row {
        id: row
        spacing: Theme.gap
        // Padlock drawn from two rectangles, so it needs no glyph font.
        Item {
            visible: p.forced
            anchors.verticalCenter: parent.verticalCenter
            width: 8
            height: 11
            Rectangle {
                x: 1.5; y: 0; width: 5; height: 6
                radius: 2.5
                color: "transparent"
                border.width: 1.5
                border.color: Theme.dim
            }
            Rectangle {
                y: 5; width: 8; height: 6
                radius: 1.5
                color: Theme.dim
            }
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            anchors.verticalCenter: parent.verticalCenter
            color: p.forced ? Theme.dim : Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: String(p.prov.value ?? "")
        }
        Chip {
            anchors.verticalCenter: parent.verticalCenter
            text: p.prov.source ?? ""
            edge: Theme.outline
        }
    }
    HoverHandler { id: hover }

    // Note is only instantiated while hovered or focused (nothing exists at idle).
    Loader {
        active: (hover.hovered || p.activeFocus) && p.note !== ""
        y: p.height + Theme.xs
        sourceComponent: Rectangle {
            width: noteText.implicitWidth + 2 * Theme.gap
            height: noteText.implicitHeight + Theme.gap
            radius: Theme.rSm
            color: Theme.containerHigh
            border.width: 1
            border.color: Theme.outline
            Text {
                id: noteText
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                anchors.centerIn: parent
                color: Theme.fg
                font.pixelSize: Theme.fsLabel
                font.family: Theme.fam(text, Theme.families)
                text: p.note
            }
        }
    }
    FocusRing {
        anchors.fill: parent
        shown: p.activeFocus
        corner: Theme.rSm
    }
}
