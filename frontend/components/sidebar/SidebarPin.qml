import QtQuick
import "../../core"
import "../island"
import "../../surfaces" as S

// The sidebar's pin (session 20, K84): kept open while pinned (`sidebar.<side>.pinned`; the daemon lays it out as
// "always shown"), back to the chosen visibility when unpinned. In the header's button row when the header tops the
// column, else in a row of its own at the column's top (Sidebar.qml).
KeyButton {
    id: pin
    property string sidebarSide: "right"
    S.BarConfig { id: cfg; screen: null }
    readonly property bool pinned: cfg.valueOf("sidebar." + sidebarSide + ".pinned", false) === true
    objectName: "sidebar-pin-" + sidebarSide
    icon: "push_pin"
    glyph: "⌖"
    side: 32
    primary: pinned
    a11y: I18n.tr(pinned ? "sidebar.unpin" : "sidebar.pin")
    onClicked: Store.apply([{ set: "sidebar." + sidebarSide + ".pinned", value: !pinned }])
}
