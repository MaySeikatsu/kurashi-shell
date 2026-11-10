import QtQuick
import "../../core"
import ".."

// A control's tile (W70): QuickTile drawn from one Control (quick/*Control.qml) — its mark, name, value, reason, who holds
// it, its request and whether it has a page. The host says what a page or a secondary press opens.
// In the centre's edit mode (`editing`) the tile is a thing to arrange: a drag moves it (`dragTo` reports the pointer in
// `dragArea`'s coordinates while it is held, `dragEnded` when it is let go), its remove key (−) takes it out of the centre.
QuickTile {
    id: ct
    property var ctl: null
    property Item dragArea: null
    signal removeRequested()
    signal dragTo(real ax, real ay)
    signal dragEnded()
    glyph: ctl ? ctl.glyph : ""
    icon: ctl ? ctl.icon : ""
    label: ctl ? ctl.label : ""
    subtitle: ctl ? ctl.value : ""
    reason: ctl ? ctl.reason : ""
    forcedBy: ctl ? ctl.forcedBy : ""
    on: ctl ? ctl.on : false
    toggles: ctl ? ctl.toggles : false
    req: ctl ? ctl.req : null
    pendingText: ctl ? ctl.pendingText : ""
    hasPage: ctl ? ctl.page !== "" : false
    Accessible.description: editing ? I18n.tr("quick.edit.tile_hint") : shownSubtitle

    // Made only in edit mode: the drag over the whole tile, and the remove key on its corner.
    Loader {
        active: ct.editing
        anchors.fill: parent
        z: 10
        sourceComponent: Item {
            MouseArea {
                id: drag
                anchors.fill: parent
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: ct.forceActiveFocus()
                onPositionChanged: mouse => {
                    if (!pressed || ct.dragArea === null) return
                    var p = drag.mapToItem(ct.dragArea, mouse.x, mouse.y)
                    ct.dragTo(p.x, p.y)
                }
                onReleased: ct.dragEnded()
                onCanceled: ct.dragEnded()
            }
            // The remove key: a small round key on the top-right corner, half outside the tile (iOS's, the desk's eye).
            Rectangle {
                id: minus
                width: 22
                height: 22
                radius: 11
                x: parent.width - width + 6
                y: -6
                color: rm.containsMouse ? Theme.error : Theme.containerHigh
                border.width: 1
                border.color: Theme.outline
                Icon {
                    anchors.centerIn: parent
                    name: "remove"
                    glyph: "−"
                    size: 16
                    color: rm.containsMouse ? Theme.surface : Theme.fg
                }
                MouseArea {
                    id: rm
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    onClicked: ct.removeRequested()
                }
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr("quick.edit.remove").replace("{name}", ct.label)
            }
        }
    }
}
