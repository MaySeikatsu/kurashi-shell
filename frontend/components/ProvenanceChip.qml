import QtQuick
import "../core"

// Shōjiki (rule 2): renders a Provenanced value {value, source, forced_by?, reason?}.
// Shows the value with a source badge; when forced_by is set the value is NOT in the user's
// control, so the chip is drawn inert and the hover note says why. No logic beyond display.
Item {
    id: p
    property var prov: ({})
    readonly property bool forced: prov.forced_by !== undefined && prov.forced_by !== null
    readonly property string note: forced
        ? I18n.tr("frontend.prov.forced_by") + " " + prov.forced_by + (prov.reason ? " · " + prov.reason : "")
        : (prov.reason ? prov.reason : "")

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: Theme.gap
        opacity: p.forced ? 0.55 : 1
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            font.strikeout: p.forced
            text: String(p.prov.value ?? "")
        }
        Chip {
            anchors.verticalCenter: parent.verticalCenter
            text: p.prov.source ?? ""
            edge: p.forced ? Theme.accent : Theme.outline
        }
    }
    HoverHandler { id: hover }

    // Note is only instantiated while hovered (nothing exists at idle).
    Loader {
        active: hover.hovered && p.note !== ""
        y: p.height + 4
        sourceComponent: Rectangle {
            width: noteText.implicitWidth + 2 * Theme.gap
            height: noteText.implicitHeight + Theme.gap
            radius: Theme.rSm
            color: Theme.containerHigh
            border.width: 1
            border.color: Theme.outline
            Text {
                id: noteText
                anchors.centerIn: parent
                color: Theme.fg
                font.pixelSize: Theme.fs - 1
                font.family: Theme.fam(text, Theme.families)
                text: p.note
            }
        }
    }
}
