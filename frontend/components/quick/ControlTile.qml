import QtQuick
import "../../core"

// A control's tile (W70): QuickTile drawn from one Control (quick/*Control.qml) — its mark, name, value, reason, who holds
// it, its request and whether it has a page. The host says what a page or a secondary press opens.
QuickTile {
    property var ctl: null
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
}
